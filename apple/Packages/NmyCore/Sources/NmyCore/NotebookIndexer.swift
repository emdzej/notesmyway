//
//  NotebookIndexer.swift
//  NmyCore
//
//  Keeps a `NotebookIndex` in step with the files. `sync()` is the full scan
//  run on open (cheap after the first time: only files whose size or
//  modification time changed are read). `update(_:)` reindexes specific
//  paths, e.g. after nmy saves a note or a file event arrives.
//

import Foundation

public struct IndexChanges: Equatable, Sendable {
    public var added: [NotebookPath] = []
    public var updated: [NotebookPath] = []
    public var removed: [NotebookPath] = []
    /// Files that couldn't be read (permissions, not UTF-8, iCloud placeholder…).
    public var failed: [NotebookPath] = []

    public var isEmpty: Bool { added.isEmpty && updated.isEmpty && removed.isEmpty }
}

public actor NotebookIndexer {
    public let index: NotebookIndex
    public var notebook: Notebook { index.notebook }

    public init(index: NotebookIndex) {
        self.index = index
    }

    /// Brings the index up to date with the whole notebook.
    @discardableResult
    public func sync() throws -> IndexChanges {
        let scanned = try NotebookScanner.scan(notebook)
        var known = try index.indexedFiles()
        var changes = IndexChanges()
        for file in scanned {
            let previous = known.removeValue(forKey: file.path)
            if let previous, previous.size == file.size, previous.mtime == file.mtime, previous.kind == file.kind { continue }
            if reindex(file) {
                if previous == nil { changes.added.append(file.path) } else { changes.updated.append(file.path) }
            } else {
                changes.failed.append(file.path)
            }
        }
        let gone = Array(known.keys)
        try index.remove(gone)
        changes.removed = gone.sorted()
        return changes
    }

    /// Reindexes `paths`: changed files are re-read, missing ones removed.
    @discardableResult
    public func update(_ paths: [NotebookPath]) throws -> IndexChanges {
        let known = try index.indexedFiles()
        var changes = IndexChanges()
        var gone: [NotebookPath] = []
        for path in Set(paths) {
            let url = notebook.url(for: path)
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
            guard values?.isRegularFile == true, !path.components.contains(where: { $0.hasPrefix(".") }) else {
                if known[path] != nil { gone.append(path) }
                continue
            }
            let file = ScannedFile(path: path, kind: FileKind(path: path), size: values?.fileSize ?? 0,
                                   mtime: NotebookScanner.millis(values?.contentModificationDate))
            if reindex(file) {
                if known[path] == nil { changes.added.append(path) } else { changes.updated.append(path) }
            } else {
                changes.failed.append(path)
            }
        }
        try index.remove(gone)
        changes.removed = gone.sorted()
        changes.added.sort()
        changes.updated.sort()
        return changes
    }

    /// Reads one file and writes its rows; false if it couldn't be read.
    private func reindex(_ file: ScannedFile) -> Bool {
        let url = notebook.url(for: file.path)
        do {
            if file.kind == .note {
                let data = try Data(contentsOf: url)
                guard let text = String(data: data, encoding: .utf8) else { return false }
                let metadata = NoteMetadata(markdown: text, fileName: file.path.stem)
                try index.upsert(file, hash: NotebookScanner.hash(of: data), note: metadata)
            } else {
                try index.upsert(file, hash: try NotebookScanner.hash(of: url), note: nil)
            }
            return true
        } catch {
            return false
        }
    }
}
