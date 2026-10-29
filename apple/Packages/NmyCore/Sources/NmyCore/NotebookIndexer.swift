//
//  NotebookIndexer.swift
//  NmyCore
//
//  Keeps a `NotebookIndex` in step with the files. `sync()` is the full scan
//  run on open (cheap after the first time: only files whose size or
//  modification time changed are read). `update(_:)` reindexes specific
//  paths (files or folders), e.g. after nmy saves a note or a file event
//  arrives. Both report moves: a file that disappeared while one with the
//  same contents appeared.
//

import Foundation

public struct IndexChanges: Equatable, Sendable {
    public var added: [NotebookPath] = []
    public var updated: [NotebookPath] = []
    public var removed: [NotebookPath] = []
    /// Old → new path of files that moved or were renamed. These paths are
    /// not repeated in `added` / `removed`.
    public var moved: [NotebookPath: NotebookPath] = [:]
    /// Files that couldn't be read (permissions, not UTF-8, iCloud placeholder…).
    public var failed: [NotebookPath] = []

    public var isEmpty: Bool { added.isEmpty && updated.isEmpty && removed.isEmpty && moved.isEmpty }
}

public actor NotebookIndexer {
    public let index: NotebookIndex
    public nonisolated var notebook: Notebook { index.notebook }

    public init(index: NotebookIndex) {
        self.index = index
    }

    /// Brings the index up to date with the whole notebook.
    @discardableResult
    public func sync() throws -> IndexChanges {
        let scanned = try NotebookScanner.scan(notebook)
        var known = try index.indexedFiles()
        var batch = Batch()
        for file in scanned {
            let previous = known.removeValue(forKey: file.path)
            batch.consider(file, previous: previous, indexer: self)
        }
        batch.gone = known
        return try batch.finish(index)
    }

    /// Reindexes `paths`: changed files are re-read, missing ones removed.
    /// A folder path covers everything inside it.
    @discardableResult
    public func update(_ paths: [NotebookPath]) throws -> IndexChanges {
        let known = try index.indexedFiles()
        var batch = Batch()
        var seen: Set<NotebookPath> = []
        for path in Set(paths) where !path.components.contains(where: { $0.hasPrefix(".") }) {
            let url = notebook.url(for: path)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                let files = isDirectory.boolValue ? (try? NotebookScanner.scan(notebook, under: path)) ?? [] : [NotebookScanner.file(at: path, in: notebook)].compactMap { $0 }
                for file in files where seen.insert(file.path).inserted {
                    batch.consider(file, previous: known[file.path], indexer: self)
                }
                if isDirectory.boolValue {
                    // Files the index has under the folder that are gone now.
                    for (knownPath, file) in known where knownPath.isInside(path) && !seen.contains(knownPath) {
                        if !FileManager.default.fileExists(atPath: notebook.url(for: knownPath).path) { batch.gone[knownPath] = file }
                    }
                }
            } else {
                // Gone: the file itself, or a folder and everything indexed under it.
                for (knownPath, file) in known where knownPath == path || knownPath.isInside(path) {
                    batch.gone[knownPath] = file
                }
            }
        }
        return try batch.finish(index)
    }

    /// Reads one file and writes its rows; returns its hash, nil if unreadable.
    fileprivate func reindex(_ file: ScannedFile) -> String? {
        let url = notebook.url(for: file.path)
        do {
            if file.kind == .note {
                let snapshot = try NoteFile(url: url).read()
                let hash = NotebookScanner.hash(of: (snapshot.hasByteOrderMark ? Data([0xEF, 0xBB, 0xBF]) : Data()) + Data(snapshot.text.utf8))
                try index.upsert(file, hash: hash, note: NoteMetadata(markdown: snapshot.text, fileName: file.path.stem))
                return hash
            }
            let hash = try NotebookScanner.hash(of: url)
            try index.upsert(file, hash: hash, note: nil)
            return hash
        } catch {
            return nil
        }
    }

    /// Collects one sync / update pass, then pairs moves and removes the gone.
    private struct Batch {
        var added: [(NotebookPath, String)] = []
        var updated: [NotebookPath] = []
        var failed: [NotebookPath] = []
        var gone: [NotebookPath: IndexedFile] = [:]

        mutating func consider(_ file: ScannedFile, previous: IndexedFile?, indexer: isolated NotebookIndexer) {
            if let previous, previous.size == file.size, previous.mtime == file.mtime, previous.kind == file.kind { return }
            guard let hash = indexer.reindex(file) else { failed.append(file.path); return }
            if previous == nil { added.append((file.path, hash)) } else { updated.append(file.path) }
        }

        func finish(_ index: NotebookIndex) throws -> IndexChanges {
            var changes = IndexChanges()
            // A gone file and a new one with the same (unambiguous) contents is a move.
            var goneByHash: [String: [NotebookPath]] = [:]
            for (path, file) in gone { if let hash = file.hash { goneByHash[hash, default: []].append(path) } }
            var newByHash: [String: [NotebookPath]] = [:]
            for (path, hash) in added { newByHash[hash, default: []].append(path) }
            for (hash, olds) in goneByHash where olds.count == 1 {
                if let news = newByHash[hash], news.count == 1 { changes.moved[olds[0]] = news[0] }
            }
            let movedTo = Set(changes.moved.values)
            changes.added = added.map(\.0).filter { !movedTo.contains($0) }.sorted()
            changes.removed = gone.keys.filter { changes.moved[$0] == nil }.sorted()
            changes.updated = updated.sorted()
            changes.failed = failed.sorted()
            try index.remove(Array(gone.keys))
            return changes
        }
    }
}

extension NotebookPath {
    /// True when `self` lies below `folder`.
    func isInside(_ folder: NotebookPath) -> Bool { rawValue.hasPrefix(folder.rawValue + "/") }
}

extension NotebookScanner {
    /// Visible files under `folder`.
    static func scan(_ notebook: Notebook, under folder: NotebookPath) throws -> [ScannedFile] {
        try scan(notebook, startingAt: notebook.url(for: folder))
    }

    /// One file's scan record, nil if it isn't a visible regular file.
    static func file(at path: NotebookPath, in notebook: Notebook) -> ScannedFile? {
        let url = notebook.url(for: path)
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
              values.isRegularFile == true else { return nil }
        return ScannedFile(path: path, kind: FileKind(path: path), size: values.fileSize ?? 0, mtime: millis(values.contentModificationDate))
    }
}
