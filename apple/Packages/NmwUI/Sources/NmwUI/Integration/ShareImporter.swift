//
//  ShareImporter.swift
//  NmwUI
//
//  Turns a queued share job (from the share extension) into markdown in a
//  notebook: a new note, or an entry appended to `Inbox.md`. Shared images
//  are stored like dropped files; web links become `{.preview}` cards.
//

import Foundation
import MarkdownEngine
import NmwCore
import NmwShared
import UniformTypeIdentifiers

enum ShareImporter {

    static let inboxName = "Inbox.md"

    /// Writes `job` into `notebook` and returns the note it went to.
    static func write(_ job: ShareJob, from folder: ShareJob.Folder, into notebook: Notebook,
                      attachments: NotebookConfig.Attachments = NotebookConfig.Attachments(),
                      now: Date = Date()) throws -> NotebookPath {
        let title = job.title.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        switch job.destination {
        case .newNote:
            let noteTitle = title ?? suggestedTitle(for: job.items)
            let noteURL = uniqueNoteURL(in: notebook.root, named: noteTitle)
            let blocks = try render(job.items, from: folder, noteURL: noteURL, notebook: notebook, attachments: attachments)
            var text = "# \(noteTitle)\n"
            if let comment = job.comment?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty { text += "\n\(comment)\n" }
            for block in blocks { text += "\n\(block)\n" }
            _ = try NoteFile(url: noteURL).write(text, replacing: nil)
            return try path(of: noteURL, in: notebook)

        case .inbox:
            let noteURL = notebook.root.appending(path: inboxName, directoryHint: .notDirectory)
            let file = NoteFile(url: noteURL)
            let existing = FileManager.default.fileExists(atPath: noteURL.path) ? try file.read() : nil
            var text = existing?.text ?? "# Inbox\n"
            if !text.hasSuffix("\n") { text += "\n" }
            text += "\n## \(now.formatted(date: .abbreviated, time: .shortened))\n"
            if let title { text += "\n**\(title)**\n" }
            if let comment = job.comment?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty { text += "\n\(comment)\n" }
            for block in try render(job.items, from: folder, noteURL: noteURL, notebook: notebook, attachments: attachments) {
                text += "\n\(block)\n"
            }
            _ = try file.write(text, replacing: existing)
            return try path(of: noteURL, in: notebook)
        }
    }

    /// Markdown for each shared item.
    static func render(_ items: [ShareJob.Item], from folder: ShareJob.Folder, noteURL: URL, notebook: Notebook,
                       attachments: NotebookConfig.Attachments) throws -> [String] {
        try items.compactMap { item in
            switch item {
            case .text(let text):
                return text.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            case .url(let url, let title):
                if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                    let label = (title?.nilIfEmpty ?? url.host() ?? url.absoluteString)
                        .replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
                    return "[\(label)](\(url.absoluteString)){.preview}"
                }
                return "<\(url.absoluteString)>"
            case .image(let fileName):
                let source = folder.file(fileName)
                guard FileManager.default.fileExists(atPath: source.path) else { return nil }
                let stored = try AttachmentStore.store(source, named: fileName, for: noteURL, notebookRoot: notebook.root, layout: attachments)
                let dropped = DroppedFile(url: source, contentType: UTType(filenameExtension: source.pathExtension) ?? .image, name: fileName)
                return dropped.markdownLink(to: stored.linkPath) + "{.medium}"
            }
        }
    }

    /// A title from the content: a link's title, else the first line of text.
    static func suggestedTitle(for items: [ShareJob.Item]) -> String {
        for item in items {
            if case .url(let url, let title) = item { return title?.nilIfEmpty ?? url.host() ?? "Shared Link" }
        }
        for item in items {
            if case .text(let text) = item,
               let line = text.split(whereSeparator: \.isNewline).first.map({ String($0).trimmingCharacters(in: .whitespaces) }),
               !line.isEmpty {
                return String(line.prefix(60))
            }
        }
        return items.contains { if case .image = $0 { true } else { false } } ? "Shared Image" : "Shared Note"
    }

    /// `<folder>/<name>.md`, numbered (`<name> 2.md`) if taken.
    static func uniqueNoteURL(in folder: URL, named name: String) -> URL {
        var base = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        if base.isEmpty { base = "Untitled" }
        base = String(base.prefix(80))
        var candidate = folder.appending(path: "\(base).md", directoryHint: .notDirectory)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appending(path: "\(base) \(n).md", directoryHint: .notDirectory)
            n += 1
        }
        return candidate
    }

    private static func path(of url: URL, in notebook: Notebook) throws -> NotebookPath {
        guard let path = notebook.path(for: url) else { throw CocoaError(.fileWriteInvalidFileName) }
        return path
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
