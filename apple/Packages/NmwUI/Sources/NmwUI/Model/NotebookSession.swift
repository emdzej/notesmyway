//
//  NotebookSession.swift
//  NmwUI
//
//  One open notebook: its index, watcher and preview store, what the
//  sidebar and note list show, and the file operations (new, rename, move,
//  pin, delete). Moves keep links working by applying the index's link
//  edits, with one undo for the whole fix.
//

import Foundation
import NmwCore
import Observation

public struct FolderNode: Identifiable, Hashable, Sendable {
    public var id: NotebookPath { path }
    public let path: NotebookPath
    public var name: String { path.name }
    /// nil for leaves, so `OutlineGroup` shows no disclosure triangle.
    public var children: [FolderNode]?
}

/// What a move did, for the "Renamed … · Updated links in N notes · Undo" banner.
public struct LinkFixSummary: Identifiable, Sendable {
    public let id = UUID()
    public let notes: [NotebookPath]
    /// Notes that changed in the meantime and were left alone.
    public let skipped: [NotebookPath]
    /// The move nmw made (old → new), undone along with the link edits; nil
    /// for moves made outside nmw.
    public let move: (from: NotebookPath, to: NotebookPath)?
    let undo: [NoteEdit]
}

@MainActor
@Observable
public final class NotebookSession {

    public enum Scope: Hashable, Sendable {
        case all, pinned
        case folder(NotebookPath?)
        case tag(String)
    }

    public let notebook: Notebook
    public let index: NotebookIndex
    public let previews: LinkPreviewStore
    @ObservationIgnored let indexer: NotebookIndexer

    public var scope: Scope = .all { didSet { if scope != oldValue { refreshNotes() } } }
    public var sort: NoteSort = .modified { didSet { refreshNotes() } }
    public var searchText = "" { didSet { if searchText != oldValue { refreshNotes() } } }
    public var selection: NotebookPath?
    /// Rewrite links automatically when files move (spec §6, default on).
    public var fixesLinksOnMove = true

    public private(set) var notes: [NoteSummary] = []
    public private(set) var folders: [FolderNode] = []
    public private(set) var tags: [TagCount] = []
    public private(set) var isIndexing = false
    public private(set) var errorMessage: String?
    public var linkFix: LinkFixSummary?
    /// Bumped when previews load or files change; part of the editor's fingerprint.
    public private(set) var contentVersion = 0

    /// Folders the user collapsed in the sidebar (all start expanded).
    public var collapsedFolders: Set<NotebookPath> = []

    /// The quick switcher (⌘O) is showing.
    public var isShowingSwitcher = false

    @ObservationIgnored private var editors: [NotebookPath: NoteEditorModel] = [:]
    /// The move being made by nmw itself, so its banner can offer undoing it.
    @ObservationIgnored private var ownMove: (from: NotebookPath, to: NotebookPath)?
    @ObservationIgnored private var watchTask: Task<Void, Never>?

    public var name: String { notebook.name }

    /// - Parameter indexURL: where the index lives; nil keeps it in memory (tests).
    public init(notebook: Notebook, indexURL: URL?, cacheFolder: URL) throws {
        self.notebook = notebook
        index = try NotebookIndex(notebook: notebook, at: indexURL)
        indexer = NotebookIndexer(index: index)
        let bump = Bump()
        previews = LinkPreviewStore(cacheFolder: cacheFolder, index: index, onChange: { bump.fire() })
        bump.action = { [weak self] in self?.contentVersion += 1 }
    }

    /// Scans the folder, then follows changes until `stop()`.
    public func start() async {
        guard watchTask == nil else { return }
        purgeTrash()
        isIndexing = true
        do { try await indexer.sync() } catch { errorMessage = error.localizedDescription }
        isIndexing = false
        refresh()
        let stream = NotebookWatcher.changes(of: indexer)
        watchTask = Task { [weak self] in
            for await changes in stream {
                await self?.apply(changes)
            }
        }
    }

    public func stop() {
        watchTask?.cancel()
        watchTask = nil
        for editor in editors.values { editor.flush() }
    }

    // MARK: Lists

    public func refresh() {
        refreshNotes()
        tags = (try? index.tags()) ?? []
        folders = Self.folderTree(in: notebook)
    }

    private func refreshNotes() {
        do {
            if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                var query = searchText
                switch scope {
                case .folder(let folder?): query += " path:\"\(folder.rawValue)/\""
                case .tag(let tag): query += " tag:\(tag)"
                default: break
                }
                notes = try index.search(query)
                if scope == .pinned { notes = notes.filter(\.pinned) }
            } else {
                switch scope {
                case .all: notes = try index.notes(sortedBy: sort)
                case .pinned: notes = try index.notes(sortedBy: sort).filter(\.pinned)
                // A folder lists its notes and its subfolders' notes; the notebook root only its own.
                case .folder(let folder): notes = try index.notes(in: folder, recursive: folder != nil, sortedBy: sort)
                case .tag(let tag): notes = try index.notes(taggedWith: tag, sortedBy: sort)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Visible folders, excluding `_attachments`.
    static func folderTree(in notebook: Notebook) -> [FolderNode] {
        func children(of url: URL) -> [FolderNode] {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])) ?? []
            return contents.compactMap { child -> FolderNode? in
                guard (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                      child.lastPathComponent != "_attachments", let path = notebook.path(for: child) else { return nil }
                let sub = children(of: child)
                return FolderNode(path: path, children: sub.isEmpty ? nil : sub)
            }.sorted { $0.path < $1.path }
        }
        return children(of: notebook.root)
    }

    // MARK: Editors

    /// The editor model for `path`, shared by every view showing it.
    public func editor(for path: NotebookPath) -> NoteEditorModel {
        if let existing = editors[path] { return existing }
        let model = NoteEditorModel(url: notebook.url(for: path))
        model.onSaved = { [weak self] url in self?.fileSaved(url) }
        editors[path] = model
        return model
    }

    /// Saves and forgets editors other than `keep` (call when the selection changes).
    public func closeEditors(except keep: NotebookPath?) {
        for (path, editor) in editors where path != keep {
            editor.flush()
            editors[path] = nil
        }
    }

    private func fileSaved(_ url: URL) {
        guard let path = notebook.path(for: url) else { return }
        Task {
            if let changes = try? await indexer.update([path]) { await apply(changes, fromSave: true) }
        }
    }

    // MARK: Changes

    func apply(_ changes: IndexChanges, fromSave: Bool = false) async {
        guard !changes.isEmpty else { return }
        // Open editors follow moves, and pick up outside edits.
        for (old, new) in changes.moved {
            if let editor = editors.removeValue(forKey: old) {
                editor.fileMoved(to: notebook.url(for: new))
                editors[new] = editor
            }
            if selection == old { selection = new }
        }
        if !fromSave {
            for path in changes.updated { editors[path]?.diskDidChange() }
        }
        if !changes.moved.isEmpty, fixesLinksOnMove {
            fixLinks(after: changes.moved)
        }
        if case .folder(let folder?) = scope, changes.moved.keys.contains(where: { $0.isInside(folder) }),
           !FileManager.default.fileExists(atPath: notebook.url(for: folder).path) {
            scope = .folder(folder.parent)
        }
        if let selected = selection, changes.removed.contains(selected) { selection = nil }
        contentVersion += 1
        refresh()
    }

    /// Applies the index's link edits for `moves`, through open editors where there are any.
    func fixLinks(after moves: [NotebookPath: NotebookPath]) {
        let move = ownMove
        ownMove = nil
        let edits = (try? index.linkEdits(for: moves)) ?? []
        guard !edits.isEmpty || move != nil else { return }
        var applied: [NoteEdit] = []
        var skipped: [NotebookPath] = []
        for edit in edits {
            if write(edit.newText, to: edit.path, expecting: edit.oldText) {
                applied.append(edit)
            } else {
                skipped.append(edit.path)
            }
        }
        linkFix = LinkFixSummary(notes: applied.map(\.path), skipped: skipped, move: move,
                                 undo: applied.map { NoteEdit(path: $0.path, oldText: $0.newText, newText: $0.oldText) })
        Task { _ = try? await indexer.update(applied.map(\.path)) }
    }

    /// Reverts the last link fix (notes changed since are left alone), and
    /// moves the file or folder back when nmw moved it.
    public func undoLinkFix() async {
        guard let fix = linkFix else { return }
        linkFix = nil
        for edit in fix.undo { _ = write(edit.newText, to: edit.path, expecting: edit.oldText) }
        _ = try? await indexer.update(fix.undo.map(\.path))
        if let move = fix.move {
            let fixes = fixesLinksOnMove
            fixesLinksOnMove = false   // the edits above already restored the links
            defer { fixesLinksOnMove = fixes }
            _ = try? await self.move(move.to, to: move.from)
            linkFix = nil
        }
    }

    /// Writes `text` if the note still holds `expected` (in its editor or on disk).
    private func write(_ text: String, to path: NotebookPath, expecting expected: String) -> Bool {
        if let editor = editors[path] { return editor.applyEdit(from: expected, to: text) }
        let file = NoteFile(url: notebook.url(for: path))
        guard let snapshot = try? file.read(), snapshot.text == expected else { return false }
        return (try? file.write(text, replacing: snapshot)) != nil
    }

    // MARK: File operations

    /// Creates `Untitled.md` (or `Untitled 2.md`, …) in `folder` and selects it.
    @discardableResult
    public func createNote(in folder: NotebookPath?) async throws -> NotebookPath {
        let base = folder.map(notebook.url(for:)) ?? notebook.root
        var name = "Untitled.md"
        var n = 2
        while FileManager.default.fileExists(atPath: base.appending(path: name).path) {
            name = "Untitled \(n).md"
            n += 1
        }
        let url = base.appending(path: name)
        try NoteFile(url: url).write("", replacing: nil)
        guard let path = notebook.path(for: url) else { throw CocoaError(.fileWriteInvalidFileName) }
        if let changes = try? await indexer.update([path]) { await apply(changes, fromSave: true) }
        selection = path
        return path
    }

    /// Renames the file (the extension is kept) and fixes links to it.
    @discardableResult
    public func rename(_ path: NotebookPath, to newName: String) async throws -> NotebookPath {
        var name = newName.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        guard !name.isEmpty, !name.hasPrefix(".") else { throw CocoaError(.fileWriteInvalidFileName) }
        if (name as NSString).pathExtension.lowercased() != path.pathExtension, !path.pathExtension.isEmpty {
            name += "." + path.pathExtension
        }
        let target = path.parent.flatMap { $0.appending(name) } ?? NotebookPath(name)
        guard let target else { throw CocoaError(.fileWriteInvalidFileName) }
        return try await move(path, to: target)
    }

    /// Moves a file into `folder` (nil = notebook root) and fixes links.
    @discardableResult
    public func move(_ path: NotebookPath, toFolder folder: NotebookPath?) async throws -> NotebookPath {
        let target = folder.flatMap { $0.appending(path.name) } ?? NotebookPath(path.name)
        guard let target else { throw CocoaError(.fileWriteInvalidFileName) }
        return try await move(path, to: target)
    }

    private func move(_ path: NotebookPath, to target: NotebookPath) async throws -> NotebookPath {
        guard target != path else { return path }
        editors[path]?.flush()
        let from = notebook.url(for: path)
        let to = notebook.url(for: target)
        // A case-only rename on a case-insensitive volume is allowed.
        if FileManager.default.fileExists(atPath: to.path), path.rawValue.lowercased() != target.rawValue.lowercased() {
            throw CocoaError(.fileWriteFileExists)
        }
        for (open, editor) in editors where open == path || open.isInside(path) { editor.flush() }
        try FileManager.default.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.coordinatedMove(from, to)
        ownMove = (path, target)
        var changes = try await indexer.update([path, target])
        // A file move nmw made itself is known even if the hash pairing were ambiguous.
        if changes.moved.isEmpty, !isDirectory(target) {
            changes.moved = [path: target]
            changes.added.removeAll { $0 == target }
            changes.removed.removeAll { $0 == path }
        }
        await apply(changes, fromSave: true)
        ownMove = nil
        return target
    }

    private func isDirectory(_ path: NotebookPath) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: notebook.url(for: path).path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Creates the note a link points to but which doesn't exist yet, titled
    /// after its file name, and selects it.
    @discardableResult
    public func createMissingNote(at path: NotebookPath) async throws -> NotebookPath {
        let url = notebook.url(for: path)
        guard !FileManager.default.fileExists(atPath: url.path) else { selection = path; return path }
        try NoteFile(url: url).write("# \(path.stem)\n", replacing: nil)
        if let changes = try? await indexer.update([path]) { await apply(changes, fromSave: true) }
        selection = path
        return path
    }

    // MARK: Folders

    /// Creates `name` inside `parent` (nil = root): `New Folder`, `New Folder 2`, …
    @discardableResult
    public func createFolder(named name: String = "New Folder", in parent: NotebookPath?) throws -> NotebookPath {
        let base = parent.map(notebook.url(for:)) ?? notebook.root
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        guard !clean.isEmpty, !clean.hasPrefix("."), clean != "_attachments" else { throw CocoaError(.fileWriteInvalidFileName) }
        var candidate = clean
        var n = 2
        while FileManager.default.fileExists(atPath: base.appending(path: candidate).path) {
            candidate = "\(clean) \(n)"
            n += 1
        }
        let url = base.appending(path: candidate, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        guard let path = notebook.path(for: url) else { throw CocoaError(.fileWriteInvalidFileName) }
        folders = Self.folderTree(in: notebook)
        return path
    }

    /// Renames a folder; links into it (and out of the notes in it) are fixed.
    @discardableResult
    public func renameFolder(_ folder: NotebookPath, to newName: String) async throws -> NotebookPath {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        guard !name.isEmpty, !name.hasPrefix("."), name != "_attachments" else { throw CocoaError(.fileWriteInvalidFileName) }
        guard let target = folder.parent.flatMap({ $0.appending(name) }) ?? NotebookPath(name) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let selectedInside = scope == .folder(folder)
        let moved = try await move(folder, to: target)
        if selectedInside { scope = .folder(moved) }
        return moved
    }

    /// Moves a folder, with everything in it, to `.nmw/trash/`.
    public func moveFolderToTrash(_ folder: NotebookPath) async throws {
        try await moveToTrash(folder)
        if case .folder(let f?) = scope, f == folder || f.isInside(folder) { scope = .folder(folder.parent) }
    }

    /// Sets or clears `pinned: true` in the note's frontmatter.
    public func setPinned(_ path: NotebookPath, _ pinned: Bool) async throws {
        let value: Frontmatter.Value? = pinned ? .scalar("true") : nil
        if let editor = editors[path] {
            editor.text = Frontmatter.setting("pinned", to: value, in: editor.text)
            editor.flush()
        } else {
            let file = NoteFile(url: notebook.url(for: path))
            let snapshot = try file.read()
            try file.write(Frontmatter.setting("pinned", to: value, in: snapshot.text), replacing: snapshot)
            if let changes = try? await indexer.update([path]) { await apply(changes, fromSave: true) }
        }
    }

    /// Moves a note (or folder) to `.nmw/trash/` (kept 30 days, spec §3.1).
    public func moveToTrash(_ path: NotebookPath) async throws {
        for (open, editor) in editors where open == path || open.isInside(path) {
            editor.flush()
            editors[open] = nil
        }
        let trash = notebook.root.appending(path: ".nmw/trash", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970)
        let target = trash.appending(path: "\(stamp) \(path.rawValue.replacingOccurrences(of: "/", with: " - "))")
        try Self.coordinatedMove(notebook.url(for: path), target)
        if let selected = selection, selected == path || selected.isInside(path) { selection = nil }
        if let changes = try? await indexer.update([path]) { await apply(changes, fromSave: true) }
    }

    /// Deletes trashed items older than `days` (by the time they were trashed).
    public func purgeTrash(olderThan days: Int = 30, now: Date = Date()) {
        let trash = notebook.root.appending(path: ".nmw/trash", directoryHint: .isDirectory)
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: trash.path) else { return }
        let cutoff = now.timeIntervalSince1970 - Double(days) * 86_400
        for item in items {
            // Names start with the Unix time they were trashed at.
            guard let stamp = item.split(separator: " ", maxSplits: 1).first.flatMap({ TimeInterval($0) }), stamp < cutoff else { continue }
            try? FileManager.default.removeItem(at: trash.appending(path: item))
        }
    }

    static func coordinatedMove(_ from: URL, _ to: URL) throws {
        var coordinationError: NSError?
        var moveError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: from, options: .forMoving, writingItemAt: to, options: .forReplacing,
                               error: &coordinationError) { source, destination in
            do {
                try FileManager.default.moveItem(at: source, to: destination)
                coordinator.item(at: source, didMoveTo: destination)
            } catch {
                moveError = error
            }
        }
        if let error = coordinationError ?? moveError { throw error }
    }

    /// The notebook path for a URL inside this notebook.
    public func path(for url: URL) -> NotebookPath? { notebook.path(for: url) }
}

/// Lets the preview store's background callback reach main-actor state.
@MainActor
final class Bump {
    var action: (() -> Void)?
    nonisolated func fire() { Task { @MainActor in self.action?() } }
}
