//
//  Notebook.swift
//  NmwCore
//
//  A notebook is any folder of markdown files. Scanning lists its notes and
//  attachments, skipping hidden files and folders (`.nmw`, `.obsidian`,
//  `.git`, …). A file outside every notebook opens standalone; `Notebook.root(enclosing:)`
//  finds the notebook a file belongs to, if any.
//

import CryptoKit
import Foundation

public struct Notebook: Hashable, Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root.standardizedFileURL
    }

    public var name: String { root.lastPathComponent }

    /// Stable per device and folder; names the notebook's index file.
    public var localID: String {
        let digest = SHA256.hash(data: Data(root.resolvingSymlinksInPath().path.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    public func url(for path: NotebookPath) -> URL { path.url(in: root) }

    public func path(for url: URL) -> NotebookPath? { NotebookPath(url: url, root: root) }

    /// Nearest ancestor folder marked as a notebook (`.nmw/` or `.obsidian/`),
    /// for opening a file in its notebook rather than standalone.
    public static func root(enclosing url: URL) -> URL? {
        var folder = url.standardizedFileURL.deletingLastPathComponent()
        let fm = FileManager.default
        while folder.pathComponents.count > 1 {
            for marker in [".nmw", ".obsidian"] {
                var isDirectory: ObjCBool = false
                if fm.fileExists(atPath: folder.appending(path: marker).path, isDirectory: &isDirectory), isDirectory.boolValue {
                    return folder
                }
            }
            folder.deleteLastPathComponent()
        }
        return nil
    }
}

public enum FileKind: String, Sendable, Codable {
    case note, attachment, other

    public static let noteExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]

    public init(path: NotebookPath) {
        if Self.noteExtensions.contains(path.pathExtension) {
            self = .note
        } else if path.components.contains("_attachments") {
            self = .attachment
        } else {
            self = .other
        }
    }
}

/// A file found by scanning, with what's needed to detect changes.
public struct ScannedFile: Hashable, Sendable {
    public let path: NotebookPath
    public let kind: FileKind
    public let size: Int
    /// Modification time in whole milliseconds since 1970 (what the index stores).
    public let mtime: Int64
}

public enum NotebookScanner {
    /// Every visible file in the notebook. Hidden names (leading `.`) are skipped,
    /// and so is everything inside hidden folders.
    public static func scan(_ notebook: Notebook) throws -> [ScannedFile] {
        try scan(notebook, startingAt: notebook.root)
    }

    static func scan(_ notebook: Notebook, startingAt start: URL) throws -> [ScannedFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: start, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { throw CocoaError(.fileReadNoSuchFile) }

        var files: [ScannedFile] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true, let path = notebook.path(for: url) else { continue }
            files.append(ScannedFile(
                path: path,
                kind: FileKind(path: path),
                size: values.fileSize ?? 0,
                mtime: millis(values.contentModificationDate)
            ))
        }
        return files
    }

    static func millis(_ date: Date?) -> Int64 {
        Int64(((date?.timeIntervalSince1970 ?? 0) * 1000).rounded())
    }

    static func hash(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// sha256 of a file, streamed.
    static func hash(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
