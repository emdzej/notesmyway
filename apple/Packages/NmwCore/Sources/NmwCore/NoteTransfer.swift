//
//  NoteTransfer.swift
//  NmwCore
//
//  Moving a note to another notebook ("Move to Notebook…"): the note is
//  written in the target first, the files it links to in its attachment
//  folder are copied to the target's attachment folder (per that
//  notebook's settings) and its links to them rewritten; only then is the
//  original removed. Links from other notes to it are left as they are —
//  the caller warns about those.
//

import Foundation

public enum NoteTransfer {

    public struct Result: Equatable, Sendable {
        /// The note in the target notebook.
        public let path: NotebookPath
        /// Copied attachments, in the target.
        public let attachments: [URL]
    }

    /// Moves the note at `source` (in `from`) into `folder` of `to`.
    /// - Parameter text: the note's current text (e.g. from an open editor);
    ///   nil reads it from disk.
    @discardableResult
    public static func move(_ source: NotebookPath, from: Notebook, fromConfig: NotebookConfig,
                            to: Notebook, toConfig: NotebookConfig, folder: NotebookPath? = nil,
                            text: String? = nil) throws -> Result {
        let sourceURL = from.url(for: source)
        let sourceFile = NoteFile(url: sourceURL)
        let snapshot = try sourceFile.read()
        let original = text ?? snapshot.text

        // Where it goes: same name, numbered if taken.
        let wanted = folder.flatMap { $0.appending(source.name) } ?? NotebookPath(source.name)
        guard let wanted else { throw CocoaError(.fileWriteInvalidFileName) }
        let target = NotebookTrash.freePath(for: wanted, in: to)
        let targetURL = to.url(for: target)

        // Attachments it links to in its own attachment folder.
        let attachmentFolder = AttachmentStore.folder(for: sourceURL, notebookRoot: from.root, layout: fromConfig.attachments)
            .standardizedFileURL.path + "/"
        var replacements: [(Range<String.Index>, String)] = []
        var copied: [URL: StoredAttachment] = [:]
        try FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        for occurrence in LinkScanner.occurrences(in: original) {
            guard case .file(let url, let fragment)? = LinkTarget.resolve(occurrence.destination, from: sourceURL, root: from.root),
                  url.standardizedFileURL.path.hasPrefix(attachmentFolder),
                  FileManager.default.fileExists(atPath: url.path) else { continue }
            let stored = try copied[url] ?? AttachmentStore.store(url, for: targetURL, notebookRoot: to.root, layout: toConfig.attachments)
            copied[url] = stored
            var destination = LinkPath.encode(stored.linkPath)
            if let fragment { destination += "#" + (fragment.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? fragment) }
            replacements.append((occurrence.range, destination))
        }
        var moved = original
        for (range, replacement) in replacements.sorted(by: { $0.0.lowerBound > $1.0.lowerBound }) {
            moved.replaceSubrange(range, with: replacement)
        }

        // Write the target, check it, and only then remove the original.
        let targetFile = NoteFile(url: targetURL)
        try targetFile.write(moved, replacing: nil)
        guard (try? targetFile.read().text) == moved else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.removeItem(at: sourceURL)
        return Result(path: target, attachments: copied.values.map(\.url).sorted { $0.path < $1.path })
    }
}

public enum NoteTitle {

    /// The file name (without extension) a note titled `title` gets when
    /// files follow their first heading; nil when the title can't name a
    /// file (empty, "Untitled…").
    public static func fileStem(for title: String) -> String? {
        var stem = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        while stem.hasPrefix(".") { stem.removeFirst() }
        stem = stem.trimmingCharacters(in: .whitespaces)
        if stem.count > 120 { stem = String(stem.prefix(120)).trimmingCharacters(in: .whitespaces) }
        guard !stem.isEmpty, !stem.lowercased().hasPrefix("untitled") else { return nil }
        return stem
    }

    /// The text of the note's first `# heading`, if it has one.
    public static func firstHeading(in markdown: String) -> String? {
        let title = NoteMetadata(markdown: markdown, fileName: "").title
        return title.isEmpty ? nil : title
    }
}
