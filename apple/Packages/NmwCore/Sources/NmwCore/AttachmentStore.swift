//
//  AttachmentStore.swift
//  NmwCore
//
//  Where dropped and pasted files go (spec §4.2), per the notebook's
//  settings: `<note's folder>/.attachments/` (default) or
//  `<root>/.attachments/<note>/`. Standalone files always use the folder
//  next to them. Names are kept; a clash gets " 2", " 3", … unless the
//  existing file has the same contents, which is then reused.
//

import Foundation

public struct StoredAttachment: Equatable, Sendable {
    /// The stored copy.
    public let url: URL
    /// Destination to write in the note: relative to the note, unencoded
    /// (pass through `LinkPath.encode`, or the editor's `DroppedFile.markdownLink(to:)`).
    public let linkPath: String
    /// True when an identical file was already there and nothing was copied.
    public let reused: Bool
}

public enum AttachmentStore {

    /// The folder a note's attachments go to.
    public static func folder(for noteURL: URL, notebookRoot: URL?,
                              layout: NotebookConfig.Attachments = NotebookConfig.Attachments()) -> URL {
        let name = NotebookConfig.Attachments.isValidFolderName(layout.folderName) ? layout.folderName : ".attachments"
        guard layout.placement == .notebookRoot, let notebookRoot else {
            return noteURL.deletingLastPathComponent().appending(path: name, directoryHint: .isDirectory)
        }
        let noteName = noteURL.deletingPathExtension().lastPathComponent
        return notebookRoot.appending(path: name, directoryHint: .isDirectory)
            .appending(path: noteName.isEmpty ? "Untitled" : noteName, directoryHint: .isDirectory)
    }

    /// Copies `source` into the note's attachment folder.
    /// - Parameter name: file name to keep; defaults to the source's.
    public static func store(_ source: URL, named name: String? = nil, for noteURL: URL, notebookRoot: URL?,
                             layout: NotebookConfig.Attachments = NotebookConfig.Attachments()) throws -> StoredAttachment {
        let folder = folder(for: noteURL, notebookRoot: notebookRoot, layout: layout)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let wanted = sanitized(name ?? source.lastPathComponent)

        let sourceHash = try NotebookScanner.hash(of: source)
        var candidate = wanted
        var n = 1
        while FileManager.default.fileExists(atPath: folder.appending(path: candidate).path) {
            let existing = folder.appending(path: candidate)
            if (try? NotebookScanner.hash(of: existing)) == sourceHash {
                return StoredAttachment(url: existing, linkPath: LinkPath.relative(from: noteURL, to: existing), reused: true)
            }
            n += 1
            candidate = numbered(wanted, n)
        }

        let target = folder.appending(path: candidate, directoryHint: .notDirectory)
        var copyError: Error?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: source, options: .withoutChanges,
                                       writingItemAt: target, options: .forReplacing,
                                       error: &coordinationError) { readURL, writeURL in
            do { try FileManager.default.copyItem(at: readURL, to: writeURL) } catch { copyError = error }
        }
        if let error = coordinationError ?? copyError { throw error }
        return StoredAttachment(url: target, linkPath: LinkPath.relative(from: noteURL, to: target), reused: false)
    }

    /// Stores image (or other) data that has no file of its own, such as a
    /// pasted screenshot, under `name` (see `pastedImageName`).
    public static func store(_ data: Data, named name: String, for noteURL: URL, notebookRoot: URL?,
                             layout: NotebookConfig.Attachments = NotebookConfig.Attachments()) throws -> StoredAttachment {
        let folder = FileManager.default.temporaryDirectory.appending(path: "nmw-paste-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appending(path: sanitized(name), directoryHint: .notDirectory)
        try data.write(to: source)
        return try store(source, named: name, for: noteURL, notebookRoot: notebookRoot, layout: layout)
    }

    /// `Pasted image 2026-10-30 at 17.20.png`, as macOS names screenshots
    /// (no colons: they aren't allowed in file names on every system).
    /// The same image pasted twice is stored once; different ones pasted
    /// within the minute get " 2", " 3", ….
    public static func pastedImageName(date: Date = Date(), fileExtension: String = "png",
                                       timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm"
        return "Pasted image \(formatter.string(from: date)).\(fileExtension)"
    }

    /// `photo.jpg`, 2 → `photo 2.jpg`; `archive.tar.gz` keeps `.gz` only, like Finder.
    static func numbered(_ name: String, _ n: Int) -> String {
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        return ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"
    }

    /// No path separators, no leading dot (hidden files aren't indexed).
    static func sanitized(_ name: String) -> String {
        var s = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        while s.hasPrefix(".") { s.removeFirst() }
        return s.isEmpty ? "file" : s.precomposedStringWithCanonicalMapping
    }
}
