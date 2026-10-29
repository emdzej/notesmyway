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
import MarkdownEngine
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
        /// Recently Deleted: `.nmw/trash`.
        case trash
    }

    public let notebook: Notebook
    public let index: NotebookIndex
    public private(set) var previews: LinkPreviewStore
    /// The notebook's settings (`.nmw/config.json`).
    public private(set) var config: NotebookConfig
    @ObservationIgnored private let cacheFolder: URL
    @ObservationIgnored private let bump = Bump()
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
    /// The notebook's own folder row is collapsed in the sidebar.
    public var isRootCollapsed = false

    /// The quick switcher (⌘O) is showing.
    public var isShowingSwitcher = false
    /// The command palette (⇧⌘P) is showing.
    public var isShowingPalette = false
    /// iPhone / iPad Settings sheet (the Mac has its Settings window).
    public var isShowingSettings = false
    /// Asks the note list to show its Rename alert for this note (palette).
    public var renameRequest: NotebookPath?
    /// Asks the note list to show its Move to Notebook picker for this note (palette).
    public var moveToNotebookRequest: NotebookPath?

    /// The editor of the selected note (format commands in the palette).
    @ObservationIgnored public weak var activeController: MarkdownEditorController?

    /// Recently Deleted, newest first.
    public private(set) var trashItems: [TrashItem] = []
    /// The selected Recently Deleted item.
    public var trashSelection: TrashItem.ID?
    public var trash: NotebookTrash { NotebookTrash(notebook: notebook) }

    /// How long typing must pause before a file is renamed after its heading.
    @ObservationIgnored public var titleRenameDelay: Duration = .milliseconds(1500)
    @ObservationIgnored private var titleRenameTask: Task<Void, Never>?
    @ObservationIgnored private var pendingTitleRename: NotebookPath?
    /// The rename made after a heading, so undoing it isn't redone on the next save.
    @ObservationIgnored private var lastTitleRename: (from: NotebookPath, to: NotebookPath)?
    /// Headings the user undid a rename for, by note: left alone while unchanged.
    @ObservationIgnored private var declinedTitles: [NotebookPath: String] = [:]

    @ObservationIgnored private var editors: [NotebookPath: NoteEditorModel] = [:]
    /// The move being made by nmw itself, so its banner can offer undoing it.
    @ObservationIgnored private var ownMove: (from: NotebookPath, to: NotebookPath)?
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    /// Told after every index change (`initial`: the scan on opening); system integration (Spotlight, widgets).
    @ObservationIgnored var onIndexChange: ((IndexChanges, _ initial: Bool) -> Void)?

    public var name: String { notebook.name }

    /// - Parameter indexURL: where the index lives; nil keeps it in memory (tests).
    public init(notebook: Notebook, indexURL: URL?, cacheFolder: URL) throws {
        self.notebook = notebook
        index = try NotebookIndex(notebook: notebook, at: indexURL)
        indexer = NotebookIndexer(index: index)
        self.cacheFolder = cacheFolder
        let config = NotebookConfig.load(for: notebook)
        self.config = config
        previews = Self.makePreviews(cacheFolder: cacheFolder, index: index, config: config, bump: bump)
        bump.action = { [weak self] in self?.contentVersion += 1 }
    }

    private static func makePreviews(cacheFolder: URL, index: NotebookIndex, config: NotebookConfig, bump: Bump) -> LinkPreviewStore {
        var options = LinkPreviewStore.Options()
        options.allowsNetwork = config.webPreviews
        return LinkPreviewStore(cacheFolder: cacheFolder, index: index, options: options, onChange: { bump.fire() })
    }

    /// Saves new settings to `.nmw/config.json` and applies them.
    public func updateConfig(_ newConfig: NotebookConfig) throws {
        guard newConfig != config else { return }
        guard NotebookConfig.Attachments.isValidFolderName(newConfig.attachments.folderName) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try newConfig.save(for: notebook)
        let previewsChanged = newConfig.webPreviews != config.webPreviews
        config = newConfig
        if previewsChanged { previews = Self.makePreviews(cacheFolder: cacheFolder, index: index, config: config, bump: bump) }
        folders = Self.folderTree(in: notebook, config: config)
        contentVersion += 1
    }

    /// Scans the folder, then follows changes until `stop()`.
    public func start() async {
        guard watchTask == nil else { return }
        purgeTrash()
        isIndexing = true
        var scanned: IndexChanges?
        do { scanned = try await indexer.sync() } catch { errorMessage = error.localizedDescription }
        isIndexing = false
        refresh()
        if let scanned { onIndexChange?(scanned, true) }
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
        folders = Self.folderTree(in: notebook, config: config)
        refreshTrash()
    }

    public func refreshTrash() {
        trashItems = trash.items()
        if let selected = trashSelection, !trashItems.contains(where: { $0.id == selected }) { trashSelection = nil }
    }

    private func refreshNotes() {
        do {
            if scope == .trash {
                notes = []
            } else if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
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
                case .trash: notes = []
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The notebook's folders, for the sidebar: hidden folders (`.name`) are
    /// left out, and so are attachment folders unless the settings show them.
    static func folderTree(in notebook: Notebook, config: NotebookConfig = NotebookConfig()) -> [FolderNode] {
        let attachments = config.attachments.folderName
        func children(of url: URL) -> [FolderNode] {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsPackageDescendants])) ?? []
            return contents.compactMap { child -> FolderNode? in
                let name = child.lastPathComponent
                guard (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
                if name == attachments {
                    guard config.attachments.showInSidebar else { return nil }
                } else if name.hasPrefix(".") {
                    return nil
                }
                guard let path = notebook.path(for: child) else { return nil }
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
        // Leaving a note renames it right away (instead of after the pause).
        if let pending = pendingTitleRename, pending != keep {
            titleRenameTask?.cancel()
            Task { await renameToTitleIfNeeded() }
        }
    }

    private func fileSaved(_ url: URL) {
        guard let path = notebook.path(for: url) else { return }
        Task {
            if let changes = try? await indexer.update([path]) { await apply(changes, fromSave: true) }
            scheduleTitleRename(path)
        }
    }

    // MARK: File names from headings

    /// With "Rename files to match the first heading" on, renames the note
    /// once typing pauses (or the note is left).
    func scheduleTitleRename(_ path: NotebookPath) {
        guard config.renameFilesToTitle, FileKind(path: path) == .note else { return }
        pendingTitleRename = path
        titleRenameTask?.cancel()
        let delay = titleRenameDelay
        titleRenameTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.renameToTitleIfNeeded()
        }
    }

    /// Renames the pending note after its first heading, through the usual
    /// rename (links fixed, banner with Undo). Skips taken names, empty or
    /// "Untitled" headings, and headings whose rename the user undid.
    func renameToTitleIfNeeded() async {
        guard let path = pendingTitleRename else { return }
        pendingTitleRename = nil
        guard config.renameFilesToTitle else { return }
        let text = editors[path]?.text ?? (try? NoteFile(url: notebook.url(for: path)).read().text)
        guard let text, let heading = NoteTitle.firstHeading(in: text), let stem = NoteTitle.fileStem(for: heading),
              stem != path.stem, declinedTitles[path] != stem else { return }
        let name = path.pathExtension.isEmpty ? stem : stem + "." + (path.name as NSString).pathExtension
        guard let target = path.parent.flatMap({ $0.appending(name) }) ?? NotebookPath(name) else { return }
        let caseOnly = target.rawValue.lowercased() == path.rawValue.lowercased()
        guard caseOnly || !FileManager.default.fileExists(atPath: notebook.url(for: target).path) else { return }
        if let renamed = try? await rename(path, to: stem) { lastTitleRename = (path, renamed) }
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
        onIndexChange?(changes, false)
    }

    /// The editor of `path` if the note is open.
    func openEditor(for path: NotebookPath) -> NoteEditorModel? { editors[path] }

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
        if let move = fix.move, let title = lastTitleRename, title.from == move.from, title.to == move.to {
            // Don't rename it again for the same heading.
            declinedTitles[move.from] = move.to.stem
            lastTitleRename = nil
        }
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
        folders = Self.folderTree(in: notebook, config: config)
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
        let target = try trash.prepare(path)
        try Self.coordinatedMove(notebook.url(for: path), target)
        if let selected = selection, selected == path || selected.isInside(path) { selection = nil }
        if let changes = try? await indexer.update([path]) { await apply(changes, fromSave: true) }
        refreshTrash()
    }

    /// Deletes trashed items older than `days` (by the time they were trashed).
    public func purgeTrash(olderThan days: Int = NotebookTrash.keepDays, now: Date = Date()) {
        trash.purge(olderThan: days, now: now)
        refreshTrash()
    }

    /// Puts a trashed note or folder back where it was ("Name 2" if that's
    /// taken) and selects it.
    @discardableResult
    public func restore(_ item: TrashItem) async throws -> NotebookPath {
        let restored = try trash.restore(item)
        if let changes = try? await indexer.update([restored]) { await apply(changes, fromSave: true) }
        refreshTrash()
        if item.isFolder {
            scope = .folder(restored)
        } else {
            scope = .folder(restored.parent)
            selection = restored
        }
        return restored
    }

    /// Deletes a trashed item for good.
    public func deleteForever(_ item: TrashItem) throws {
        try trash.delete(item)
        refreshTrash()
    }

    public func emptyTrash() throws {
        try trash.empty()
        refreshTrash()
    }

    // MARK: Other notebooks

    /// The note's current text (an open editor's, else the file's), saving
    /// the editor and closing it, before the note leaves this notebook.
    func detach(_ path: NotebookPath) -> String? {
        let text = editors[path]?.text
        editors[path]?.flush()
        editors[path] = nil
        if selection == path { selection = nil }
        if pendingTitleRename == path { pendingTitleRename = nil }
        return text
    }

    /// Re-reads `paths` after files changed outside the session's own operations.
    func reindex(_ paths: [NotebookPath]) async {
        if let changes = try? await indexer.update(paths) { await apply(changes, fromSave: true) }
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
