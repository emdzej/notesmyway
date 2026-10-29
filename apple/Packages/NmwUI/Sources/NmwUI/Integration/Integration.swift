//
//  Integration.swift
//  NmwUI
//
//  Keeps the system in step with the notebooks: Spotlight items, the
//  widget snapshot (App Group), and share-extension jobs waiting in the
//  App Group inbox (spec §5.1).
//

import Foundation
import NmwCore
import NmwShared
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
final class Integration {
    static let shared = Integration()

    weak var library: Library?
    /// Off in tests, so they don't touch the real Spotlight index or the App Group container.
    var isEnabled = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        && NSClassFromString("XCTestCase") == nil
    private var isActive = false
    private var snapshotTask: Task<Void, Never>?
    private var isImporting = false
    private let defaults = UserDefaults.standard

    private func spotlightKey(_ notebookID: String) -> String { "nmw.spotlightIndexed.\(notebookID)" }

    /// The app became active: open every notebook (so Spotlight and the
    /// widgets cover all of them) and import shared content.
    func activate(_ library: Library) {
        guard isEnabled else { return }
        self.library = library
        if !isActive {
            isActive = true
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(), nil,
                { _, _, _, _, _ in Task { @MainActor in Integration.shared.importShareJobs() } },
                AppGroup.shareJobQueuedNotification as CFString, nil, .deliverImmediately)
            for entry in library.entries { _ = library.session(for: entry.id) }
        }
        importShareJobs()
        scheduleSnapshot()
    }

    // MARK: Index changes

    /// A session indexed its notebook (`initial`: the first scan after opening) or saw changes.
    func indexDidChange(_ session: NotebookSession, _ changes: IndexChanges, initial: Bool) {
        guard isEnabled else { return }
        let notebook = session.notebook
        let id = notebook.localID
        let name = session.name
        if initial, !defaults.bool(forKey: spotlightKey(id)) {
            // First time: everything. Afterwards the scan's changes cover edits made while the app was closed.
            let paths = ((try? session.index.notes()) ?? []).map(\.path)
            defaults.set(true, forKey: spotlightKey(id))
            Task { await SpotlightIndex.index(paths, in: notebook, notebookName: name) }
        } else {
            let changed = changes.added + changes.updated + Array(changes.moved.values)
            let gone = changes.removed + Array(changes.moved.keys)
            Task {
                await SpotlightIndex.remove(gone, notebookID: id)
                await SpotlightIndex.index(changed, in: notebook, notebookName: name)
            }
        }
        scheduleSnapshot()
    }

    func notebookRemoved(_ notebookID: String) {
        guard isEnabled else { return }
        defaults.removeObject(forKey: spotlightKey(notebookID))
        Task { await SpotlightIndex.removeNotebook(notebookID) }
        scheduleSnapshot()
    }

    // MARK: Widget snapshot

    func scheduleSnapshot() {
        snapshotTask?.cancel()
        snapshotTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.writeSnapshot()
        }
    }

    private func writeSnapshot() {
        guard let library else { return }
        let snapshot = Self.snapshot(of: library)
        let previous = WidgetSnapshot.load()
        guard snapshot.notebooks != previous?.notebooks || snapshot.selectedNotebookID != previous?.selectedNotebookID else { return }
        try? snapshot.save()
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    static func snapshot(of library: Library, limit: Int = 12) -> WidgetSnapshot {
        let notebooks = library.entries.compactMap { entry -> WidgetSnapshot.Notebook? in
            guard let session = library.session(for: entry.id),
                  let notes = try? session.index.notes(sortedBy: .modified) else {
                return WidgetSnapshot.Notebook(id: entry.id, name: entry.name, pinned: [], recent: [])
            }
            func note(_ summary: NoteSummary) -> WidgetSnapshot.Note {
                WidgetSnapshot.Note(notebookID: entry.id, path: summary.path.rawValue, title: summary.title,
                                    snippet: summary.snippet, modified: summary.modified, pinned: summary.pinned)
            }
            return WidgetSnapshot.Notebook(id: entry.id, name: entry.name,
                                           pinned: notes.filter(\.pinned).prefix(limit).map(note),
                                           recent: notes.prefix(limit).map(note))
        }
        return WidgetSnapshot(notebooks: notebooks, selectedNotebookID: library.selectedID)
    }

    // MARK: Share inbox

    func importShareJobs(from inbox: URL = AppGroup.inboxFolder) {
        guard let library, !isImporting else { return }
        let pending = ShareJob.pending(in: inbox)
        guard !pending.isEmpty else { return }
        isImporting = true
        Task {
            defer { isImporting = false }
            for (job, folder) in pending {
                let session = job.notebookID.flatMap(library.session(for:)) ?? library.selectedSession
                    ?? library.entries.first.flatMap { library.session(for: $0.id) }
                guard let session else { return }
                do {
                    let path = try ShareImporter.write(job, from: folder, into: session.notebook, attachments: session.config.attachments)
                    if let changes = try? await session.indexer.update([path]) { await session.apply(changes, fromSave: true) }
                    try? FileManager.default.removeItem(at: folder.url)
                } catch {
                    // Left in the inbox; the next activation tries again.
                    continue
                }
            }
        }
    }
}
