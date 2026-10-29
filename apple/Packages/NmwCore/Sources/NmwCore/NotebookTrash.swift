//
//  NotebookTrash.swift
//  NmwCore
//
//  The notebook's trash, `.nmw/trash/` (spec §3.1): trashed notes and
//  folders are moved there as `<unix time> <path with / as " - ">`, kept
//  30 days, and can be restored to where they were. `.index.json` next to
//  them records each item's original path exactly (the name alone is
//  ambiguous when a file name contains " - ").
//

import Foundation

/// A note or folder in the trash.
public struct TrashItem: Identifiable, Hashable, Sendable {
    /// The file name inside `.nmw/trash/`.
    public let id: String
    public let url: URL
    /// Where it was in the notebook.
    public let originalPath: NotebookPath
    public let deletedAt: Date
    public let isFolder: Bool

    public var name: String { originalPath.name }
    public var isNote: Bool { !isFolder && FileKind(path: originalPath) == .note }

    /// Whole days left before the purge (0 on the last day).
    public func daysLeft(keeping days: Int = NotebookTrash.keepDays, now: Date = Date()) -> Int {
        let expires = deletedAt.addingTimeInterval(Double(days) * 86_400)
        return max(0, Int(expires.timeIntervalSince(now) / 86_400))
    }
}

public struct NotebookTrash: Sendable {
    public static let keepDays = 30

    public let notebook: Notebook
    public var folder: URL { notebook.root.appending(path: ".nmw/trash", directoryHint: .isDirectory) }
    private var indexURL: URL { folder.appending(path: ".index.json", directoryHint: .notDirectory) }

    public init(notebook: Notebook) {
        self.notebook = notebook
    }

    // MARK: Listing

    /// Everything in the trash, most recently deleted first.
    public func items() -> [TrashItem] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        let recorded = readIndex()
        return names.compactMap { name -> TrashItem? in
            guard !name.hasPrefix("."), let (stamp, encoded) = Self.split(name) else { return nil }
            let original = recorded[name].flatMap(NotebookPath.init) ?? Self.decode(encoded)
            guard let original else { return nil }
            let url = folder.appending(path: name)
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            return TrashItem(id: name, url: url, originalPath: original,
                             deletedAt: Date(timeIntervalSince1970: stamp), isFolder: isDirectory.boolValue)
        }
        .sorted { ($0.deletedAt, $0.id) > ($1.deletedAt, $1.id) }
    }

    // MARK: Changes

    /// The name `path` gets in the trash, recorded so it can be restored.
    /// Call before moving the item there (the move is the caller's, so it
    /// can coordinate it and flush open editors).
    public func prepare(_ path: NotebookPath, now: Date = Date()) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = Int(now.timeIntervalSince1970)
        let base = "\(stamp) \(path.rawValue.replacingOccurrences(of: "/", with: " - "))"
        var name = base
        var n = 2
        while FileManager.default.fileExists(atPath: folder.appending(path: name).path) {
            name = "\(base) \(n)"
            n += 1
        }
        var index = readIndex()
        index[name] = path.rawValue
        try writeIndex(index)
        return folder.appending(path: name)
    }

    /// Moves an item back to its original path; if that's taken, to
    /// "Name 2", "Name 3"… next to it. Missing parent folders are recreated.
    @discardableResult
    public func restore(_ item: TrashItem) throws -> NotebookPath {
        let target = Self.freePath(for: item.originalPath, in: notebook)
        let url = notebook.url(for: target)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: item.url, to: url)
        forget(item.id)
        return target
    }

    /// Deletes an item for good.
    public func delete(_ item: TrashItem) throws {
        try FileManager.default.removeItem(at: item.url)
        forget(item.id)
    }

    /// Deletes everything in the trash.
    public func empty() throws {
        for item in items() { try delete(item) }
        try? FileManager.default.removeItem(at: indexURL)
    }

    /// Deletes items trashed more than `days` ago.
    public func purge(olderThan days: Int = NotebookTrash.keepDays, now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        for item in items() where item.deletedAt < cutoff { try? delete(item) }
    }

    // MARK: Names

    /// `1767000000 Projects - Idea.md` → (1767000000, "Projects - Idea.md").
    static func split(_ name: String) -> (TimeInterval, String)? {
        let parts = name.split(separator: " ", maxSplits: 1)
        guard parts.count == 2, let stamp = TimeInterval(parts[0]) else { return nil }
        return (stamp, String(parts[1]))
    }

    /// Best guess for items without a record (trashed by older versions).
    static func decode(_ encoded: String) -> NotebookPath? {
        NotebookPath(encoded.replacingOccurrences(of: " - ", with: "/"))
    }

    /// `path`, or the first of "Name 2", "Name 3"… that doesn't exist.
    static func freePath(for path: NotebookPath, in notebook: Notebook) -> NotebookPath {
        func exists(_ p: NotebookPath) -> Bool { FileManager.default.fileExists(atPath: notebook.url(for: p).path) }
        guard exists(path) else { return path }
        let ext = path.pathExtension.isEmpty ? "" : "." + (path.name as NSString).pathExtension
        for n in 2... {
            let name = "\(path.stem) \(n)\(ext)"
            if let candidate = path.parent.flatMap({ $0.appending(name) }) ?? NotebookPath(name), !exists(candidate) {
                return candidate
            }
        }
        return path
    }

    // MARK: Index

    private func readIndex() -> [String: String] {
        guard let data = try? Data(contentsOf: indexURL),
              let index = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return index
    }

    private func writeIndex(_ index: [String: String]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(index).write(to: indexURL, options: .atomic)
    }

    private func forget(_ name: String) {
        var index = readIndex()
        guard index.removeValue(forKey: name) != nil else { return }
        try? writeIndex(index)
    }
}
