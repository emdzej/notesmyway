//
//  AttachmentStore.swift
//  NmyCore
//
//  Where dropped and pasted files go (spec §4.2): `_attachments/<note>/`
//  at the notebook root, or next to a standalone file. Names are kept;
//  a clash gets " 2", " 3", … unless the existing file has the same
//  contents, which is then reused.
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

    /// `<notebook root or note folder>/_attachments/<note name>/`.
    public static func folder(for noteURL: URL, notebookRoot: URL?) -> URL {
        let base = notebookRoot ?? noteURL.deletingLastPathComponent()
        let noteName = noteURL.deletingPathExtension().lastPathComponent
        return base.appending(path: "_attachments", directoryHint: .isDirectory)
            .appending(path: noteName.isEmpty ? "Untitled" : noteName, directoryHint: .isDirectory)
    }

    /// Copies `source` into the note's attachment folder.
    /// - Parameter name: file name to keep; defaults to the source's.
    public static func store(_ source: URL, named name: String? = nil, for noteURL: URL, notebookRoot: URL?) throws -> StoredAttachment {
        let folder = folder(for: noteURL, notebookRoot: notebookRoot)
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
