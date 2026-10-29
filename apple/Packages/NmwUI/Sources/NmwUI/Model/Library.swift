//
//  Library.swift
//  NmwUI
//
//  The notebooks the user added (folders, remembered as security-scoped
//  bookmarks so they reopen inside the sandbox), the open sessions, and
//  where an opened `.md` file goes: into its notebook, or a standalone window.
//

import Foundation
import NmwCore
import Observation

@MainActor
@Observable
public final class Library {

    public struct Entry: Identifiable, Hashable, Sendable {
        public let id: String
        public let url: URL
        public var name: String { url.lastPathComponent }
    }

    public private(set) var entries: [Entry] = []
    public var selectedID: String? {
        didSet { defaults.set(selectedID, forKey: Keys.selected) }
    }
    /// Files to open in their own window (outside every notebook).
    public var pendingStandaloneFiles: [URL] = []
    public private(set) var errorMessage: String?

    @ObservationIgnored private var sessions: [String: NotebookSession] = [:]
    @ObservationIgnored private var bookmarks: [String: Data] = [:]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storage: URL?

    private enum Keys {
        static let bookmarks = "nmw.notebookBookmarks"
        static let selected = "nmw.selectedNotebook"
    }

    /// - Parameter storage: base folder for indexes and caches; nil keeps
    ///   indexes in memory (tests).
    public init(defaults: UserDefaults = .standard, storage: URL? = Library.defaultStorage) {
        self.defaults = defaults
        self.storage = storage
        for data in defaults.array(forKey: Keys.bookmarks) as? [Data] ?? [] {
            if let url = Self.resolve(data) { register(url, bookmark: data) }
        }
        let saved = defaults.string(forKey: Keys.selected)
        selectedID = entries.contains { $0.id == saved } ? saved : entries.first?.id
        #if DEBUG
        // Screenshots (site, App Store): `-NmwOpenNotebook <path>` opens a
        // folder without the folder picker. A path relative to the app's
        // Documents folder works in the simulator.
        if let path = defaults.string(forKey: "NmwOpenNotebook") {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            let url = path.hasPrefix("/") ? URL(filePath: path) : documents?.appending(path: path)
            if let url { _ = add(folder: url) }
        }
        #endif
    }

    public nonisolated static var defaultStorage: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "nmw", directoryHint: .isDirectory)
    }

    public var selectedSession: NotebookSession? { selectedID.flatMap(session(for:)) }

    /// Adds a folder picked by the user (and selects it).
    @discardableResult
    public func add(folder url: URL) -> Entry? {
        _ = url.startAccessingSecurityScopedResource()
        let notebook = Notebook(root: url)
        if let existing = entries.first(where: { $0.id == notebook.localID }) {
            selectedID = existing.id
            return existing
        }
        guard let data = Self.bookmark(for: url) else {
            errorMessage = "Couldn’t remember access to “\(url.lastPathComponent)”."
            return nil
        }
        let entry = register(url, bookmark: data)
        persist()
        selectedID = entry.id
        return entry
    }

    public func remove(_ entry: Entry) {
        sessions.removeValue(forKey: entry.id)?.stop()
        entries.removeAll { $0.id == entry.id }
        bookmarks[entry.id] = nil
        entry.url.stopAccessingSecurityScopedResource()
        persist()
        if selectedID == entry.id { selectedID = entries.first?.id }
        Integration.shared.notebookRemoved(entry.id)
    }

    /// The session for a notebook, opened (and started) on first use.
    public func session(for id: String) -> NotebookSession? {
        if let session = sessions[id] { return session }
        guard let entry = entries.first(where: { $0.id == id }) else { return nil }
        let notebook = Notebook(root: entry.url)
        do {
            let session = try NotebookSession(
                notebook: notebook,
                indexURL: storage?.appending(path: "index/\(notebook.localID).sqlite"),
                cacheFolder: (storage ?? FileManager.default.temporaryDirectory).appending(path: "previews/\(notebook.localID)")
            )
            sessions[id] = session
            session.onIndexChange = { [weak session] changes, initial in
                if let session { Integration.shared.indexDidChange(session, changes, initial: initial) }
            }
            Task { await session.start() }
            return session
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Opens a `.md` file from Finder / Files: in its notebook if it's in
    /// one the library knows, otherwise standalone.
    public func open(file url: URL) {
        for entry in entries {
            if let path = Notebook(root: entry.url).path(for: url), let session = session(for: entry.id) {
                selectedID = entry.id
                session.scope = .folder(path.parent)
                session.selection = path
                return
            }
        }
        _ = url.startAccessingSecurityScopedResource()
        if !pendingStandaloneFiles.contains(url) { pendingStandaloneFiles.append(url) }
    }

    /// Stops all sessions, saving open notes.
    public func shutdown() {
        for session in sessions.values { session.stop() }
    }

    // MARK: Bookmarks

    @discardableResult
    private func register(_ url: URL, bookmark: Data) -> Entry {
        let entry = Entry(id: Notebook(root: url).localID, url: url)
        if !entries.contains(entry) { entries.append(entry) }
        bookmarks[entry.id] = bookmark
        return entry
    }

    private func persist() {
        defaults.set(entries.compactMap { bookmarks[$0.id] }, forKey: Keys.bookmarks)
    }

    private static func bookmark(for url: URL) -> Data? {
        #if os(macOS)
        try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
    }

    private static func resolve(_ data: Data) -> URL? {
        var stale = false
        #if os(macOS)
        let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
        #else
        let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        #endif
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }
}
