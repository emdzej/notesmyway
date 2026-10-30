//
//  AppleNotesImporter.swift
//  NmwCore
//
//  Writes an Apple Notes library into a notebook folder: one `.md` file per
//  note, in folders named like Notes' folders, with attachments copied
//  next to the notes (the notebook's attachment settings). The first line
//  becomes the `# title`; `created` and `pinned` go into frontmatter, and
//  the file's dates are set to the note's. Locked notes and notes in
//  Recently Deleted are skipped. Nothing in Notes' folder is changed.
//

import Foundation
import UniformTypeIdentifiers

public struct AppleNotesImporter: Sendable {
    public struct Report: Sendable, Equatable {
        public var imported = 0
        public var locked = 0
        /// Tables that couldn't be converted (a line in the note marks each).
        public var tables = 0
        public var missingAttachments = 0
        public var failures: [String] = []
        /// The folder the notes went to.
        public var destination: URL?
        /// The notes written.
        public var files: [URL] = []
    }

    public let library: AppleNotesLibrary
    /// The notebook's root, for attachment placement.
    public let notebookRoot: URL
    public var layout = NotebookConfig.Attachments()

    public init(library: AppleNotesLibrary, notebookRoot: URL, layout: NotebookConfig.Attachments = NotebookConfig.Attachments()) {
        self.library = library
        self.notebookRoot = notebookRoot
        self.layout = layout
    }

    /// Notes that will be imported (not locked, not deleted).
    public var importableCount: Int { importable.count }

    private var importable: [AppleNotesLibrary.Note] {
        let special = Set(library.folders.filter(\.isSpecial).map(\.id))
        return library.notes.filter { !$0.deleted && !$0.locked && $0.data != nil && !($0.folderID.map(special.contains) ?? false) }
    }

    /// Imports into `destination` (created if needed); `progress` gets (done, total).
    public func run(into destination: URL, progress: (Int, Int) -> Void = { _, _ in }) -> Report {
        var report = Report(destination: destination)
        let special = Set(library.folders.filter(\.isSpecial).map(\.id))
        report.locked = library.notes.filter { $0.locked && !$0.deleted && !($0.folderID.map(special.contains) ?? false) }.count
        let notes = importable

        // Every note's file first, so links between notes can point at them.
        let files = plannedFiles(for: notes, in: destination)
        let byIdentifier = Dictionary(notes.compactMap { note in files[note.id].map { (note.identifier.uppercased(), $0) } },
                                      uniquingKeysWith: { a, _ in a })

        for (index, note) in notes.enumerated() {
            defer { progress(index + 1, notes.count) }
            guard let url = files[note.id], let data = note.data else { continue }
            do {
                let body = try AppleNoteBody(data: data)
                var tables = 0, missing = 0
                let markdown = AppleNoteMarkdown.convert(body) { attachment in
                    resolve(attachment, noteURL: url, notes: byIdentifier, tables: &tables, missing: &missing)
                }
                report.tables += tables
                report.missingAttachments += missing
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try document(for: note, markdown: markdown).write(to: url, atomically: true, encoding: .utf8)
                var attributes: [FileAttributeKey: Any] = [:]
                if let created = note.created { attributes[.creationDate] = created }
                if let modified = note.modified { attributes[.modificationDate] = modified }
                if !attributes.isEmpty { try? FileManager.default.setAttributes(attributes, ofItemAtPath: url.path) }
                report.imported += 1
                report.files.append(url)
            } catch {
                report.failures.append(note.title.isEmpty ? "Untitled" : note.title)
            }
        }
        return report
    }

    // MARK: Files and folders

    /// Folder path of each Notes folder, from the account down; the account
    /// is a top folder only when notes come from more than one.
    func folderPaths() -> [Int64: [String]] {
        let byID = Dictionary(library.folders.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let usedAccounts = Set(library.folders.compactMap(\.accountID))
        let accountNames = Dictionary(library.accounts.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        var paths: [Int64: [String]] = [:]
        for folder in library.folders where !folder.isSpecial {
            var components: [String] = []
            var current: AppleNotesLibrary.Folder? = folder
            var guardCount = 0
            while let f = current, guardCount < 64 {
                components.insert(Self.fileName(f.name, fallback: "Notes"), at: 0)
                current = f.parentID.flatMap { byID[$0] }
                guardCount += 1
            }
            if usedAccounts.count > 1, let account = folder.accountID, let name = accountNames[account] {
                components.insert(Self.fileName(name, fallback: "Account"), at: 0)
            }
            paths[folder.id] = components
        }
        return paths
    }

    private func plannedFiles(for notes: [AppleNotesLibrary.Note], in destination: URL) -> [Int64: URL] {
        let folders = folderPaths()
        var taken = Set<String>()
        var files: [Int64: URL] = [:]
        for note in notes {
            var folder = destination
            for component in note.folderID.flatMap({ folders[$0] }) ?? [] {
                folder = folder.appending(path: component, directoryHint: .isDirectory)
            }
            let stem = Self.fileName(note.title, fallback: "Untitled")
            var name = stem
            var n = 2
            while taken.contains(folder.appending(path: "\(name).md").path.lowercased())
                    || FileManager.default.fileExists(atPath: folder.appending(path: "\(name).md").path) {
                name = "\(stem) \(n)"
                n += 1
            }
            let url = folder.appending(path: "\(name).md")
            taken.insert(url.path.lowercased())
            files[note.id] = url
        }
        return files
    }

    /// A name Finder and nmw accept: no `/` or `:`, no leading dot, not too long.
    static func fileName(_ title: String, fallback: String) -> String {
        var s = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix(".") { s.removeFirst() }
        if s.count > 120 { s = String(s.prefix(120)).trimmingCharacters(in: .whitespaces) }
        return s.isEmpty ? fallback : s
    }

    // MARK: Note text

    private func document(for note: AppleNotesLibrary.Note, markdown: String) -> String {
        var body = markdown
        // Notes treats the first line as the title: make it the H1.
        if let first = body.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first,
           first.range(of: #"^\s*([-*+>`|!#\\]|\d+[.)]\s)"#, options: .regularExpression) == nil,
           let range = body.range(of: String(first)) {
            body.replaceSubrange(range, with: "# " + first)
        } else if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !note.title.isEmpty {
            body = "# \(AppleNoteMarkdown.escape(note.title))\n"
        }
        var front: [String] = []
        if let created = note.created { front.append("created: \(Self.iso(created))") }
        if note.pinned { front.append("pinned: true") }
        guard !front.isEmpty else { return body }
        return "---\n" + front.joined(separator: "\n") + "\n---\n" + body
    }

    private static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    // MARK: Attachments

    private func resolve(_ ref: AppleNoteBody.Attachment, noteURL: URL, notes: [String: URL],
                         tables: inout Int, missing: inout Int) -> String? {
        let attachment = library.attachments[ref.identifier]
        let uti = attachment?.typeUTI.isEmpty == false ? attachment!.typeUTI : ref.typeUTI

        switch uti {
        case "com.apple.notes.inlinetextattachment.hashtag", "com.apple.notes.inlinetextattachment.mention":
            return attachment?.altText
        case "com.apple.notes.inlinetextattachment.link":
            let title = attachment?.altText ?? "note"
            if let token = attachment?.token, let id = Self.noteIdentifier(in: token), let target = notes[id] {
                return "[\(AppleNoteMarkdown.escape(title))](\(LinkPath.encode(LinkPath.relative(from: noteURL, to: target))))"
            }
            return AppleNoteMarkdown.escape(title)
        case "public.url":
            guard let url = attachment?.url else { return nil }
            let title = attachment?.title.flatMap { $0.isEmpty ? nil : $0 } ?? url
            return "[\(AppleNoteMarkdown.escape(title))](\(url))"
        case "com.apple.notes.table":
            if let data = attachment?.mergeableData, let table = try? AppleNoteTable(data: data), !table.cells.isEmpty {
                return table.markdown()
            }
            tables += 1
            return "*(A table from Apple Notes that couldn’t be converted.)*"
        default:
            break
        }

        guard let attachment else { missing += 1; return nil }
        // Files: the media's own file; drawings, scans and galleries: the image Notes renders.
        var source: URL?
        var name: String?
        if let mediaID = attachment.mediaID, let media = library.media[mediaID] {
            source = library.file(for: media)
            name = media.fileName
        }
        if source == nil { source = library.fallbackImage(for: attachment) }
        guard let source else { missing += 1; return nil }
        let fileName = name ?? (attachment.title.map { "\($0).\(source.pathExtension)" } ?? source.lastPathComponent)

        guard let stored = try? AttachmentStore.store(source, named: fileName, for: noteURL, notebookRoot: notebookRoot, layout: layout) else {
            missing += 1
            return nil
        }
        let link = LinkPath.encode(stored.linkPath)
        let isImage = UTType(filenameExtension: stored.url.pathExtension)?.conforms(to: .image) ?? false
        return isImage ? "![](\(link))" : "[\(AppleNoteMarkdown.escape(stored.url.lastPathComponent))](\(link))"
    }

    /// The note UUID in an inline link's token (`applenotes:note/<UUID>?…`).
    static func noteIdentifier(in token: String) -> String? {
        guard let range = token.range(of: #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#,
                                      options: .regularExpression) else { return nil }
        return token[range].uppercased()
    }
}
