//
//  Library+Integration.swift
//  NmwUI
//
//  What the system reaches the app through: `notesmyway://` links (widgets),
//  Spotlight results, and the operations App Intents (Shortcuts, Siri)
//  run. Intents run in the app's process, so they use the app's library
//  and its folder access.
//

import CoreSpotlight
import Foundation
import NmwCore
import NmwShared

/// A note as Shortcuts sees it.
public struct IntegrationNote: Sendable, Hashable, Identifiable {
    /// `<notebook id>/<path>`.
    public let id: String
    public let notebookID: String
    public let notebookName: String
    public let path: String
    public let title: String
    public let snippet: String
    public let modified: Date
}

public struct IntegrationNotebook: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
}

public enum IntegrationError: LocalizedError {
    case noNotebook, noteNotFound, folderNotFound

    public var errorDescription: String? {
        switch self {
        case .noNotebook: "Open a folder as a notebook in Notes my Way first."
        case .noteNotFound: "The note couldn’t be found."
        case .folderNotFound: "The folder couldn’t be found in the notebook."
        }
    }
}

extension Library {
    /// The app's library: the app, its menu commands and its intents share it.
    public static let shared = Library()

    /// Starts system integration (Spotlight, widgets, the share inbox); call when the app becomes active.
    public func activateIntegration() {
        Integration.shared.activate(self)
    }

    /// Opens a `notesmyway://` link; false if `url` isn't one.
    @discardableResult
    public func handle(_ url: URL) -> Bool {
        guard let link = AppLink(url: url) else { return false }
        switch link {
        case .open(let notebook, let path):
            _ = open(notebookID: notebook, path: path)
        case .new(let notebook, let folder, let text):
            Task {
                if let note = try? await createNote(notebookID: notebook, folder: folder, title: nil, body: text ?? "") {
                    _ = open(notebookID: note.notebookID, path: note.path)
                }
            }
        }
        return true
    }

    /// Opens the note behind a Spotlight result; false if it isn't one.
    @discardableResult
    public func handle(spotlightActivity activity: NSUserActivity) -> Bool {
        guard activity.activityType == CSSearchableItemActionType,
              let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let (notebookID, path) = SpotlightIndex.parse(identifier) else { return false }
        return open(notebookID: notebookID, path: path.rawValue)
    }

    /// Selects a notebook and one of its notes.
    @discardableResult
    public func open(notebookID: String, path: String) -> Bool {
        guard let notePath = NotebookPath(path), let session = session(for: notebookID) else { return false }
        selectedID = notebookID
        session.searchText = ""
        session.scope = .folder(notePath.parent)
        session.selection = notePath
        return true
    }

    // MARK: Intents

    public var integrationNotebooks: [IntegrationNotebook] {
        entries.map { IntegrationNotebook(id: $0.id, name: $0.name) }
    }

    /// Notes matching `query` (the app's search syntax) in every notebook.
    public func searchNotes(_ query: String, limit: Int = 20) -> [IntegrationNote] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return recentNotes(limit: limit) }
        let found = entries.flatMap { entry -> [IntegrationNote] in
            guard let session = session(for: entry.id), let notes = try? session.index.search(trimmed, limit: limit) else { return [] }
            return notes.map { note($0, in: entry) }
        }
        return Array(found.prefix(limit))
    }

    /// The most recently modified notes of every notebook.
    public func recentNotes(limit: Int = 20) -> [IntegrationNote] {
        let all = entries.flatMap { entry -> [IntegrationNote] in
            guard let session = session(for: entry.id), let notes = try? session.index.notes(sortedBy: .modified) else { return [] }
            return notes.prefix(limit).map { note($0, in: entry) }
        }
        return Array(all.sorted { $0.modified > $1.modified }.prefix(limit))
    }

    public func notes(withIDs ids: [String]) -> [IntegrationNote] {
        ids.compactMap { id in
            guard let (notebookID, path) = SpotlightIndex.parse(id),
                  let entry = entries.first(where: { $0.id == notebookID }),
                  let session = session(for: notebookID),
                  let summary = try? session.index.note(at: path) else { return nil }
            return note(summary, in: entry)
        }
    }

    /// The note's markdown.
    public func text(ofNote id: String) throws -> String {
        let (session, path) = try locate(id)
        return try NoteFile(url: session.notebook.url(for: path)).read().text
    }

    /// Creates a note. With a title the note starts with `# title` and the
    /// file is named after it; otherwise it's named after the text's first line.
    public func createNote(notebookID: String?, folder: String?, title: String?, body: String) async throws -> IntegrationNote {
        guard let entry = notebookID.flatMap({ id in entries.first { $0.id == id } }) ?? selectedEntry ?? entries.first,
              let session = session(for: entry.id) else { throw IntegrationError.noNotebook }
        var base = session.notebook.root
        if let folder = folder?.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")), !folder.isEmpty {
            guard let path = NotebookPath(folder) else { throw IntegrationError.folderNotFound }
            base = session.notebook.url(for: path)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: base.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw IntegrationError.folderNotFound
            }
        }
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        var text = body
        if let title { text = "# \(title)\n" + (body.isEmpty ? "" : "\n\(body)") }
        if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
        let firstLine = body.split(whereSeparator: \.isNewline).first.map {
            String($0).trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespaces))
        }
        let url = ShareImporter.uniqueNoteURL(in: base, named: title ?? firstLine?.nilIfEmpty.map { String($0.prefix(60)) } ?? "Untitled")
        _ = try NoteFile(url: url).write(text, replacing: nil)
        guard let path = session.notebook.path(for: url) else { throw IntegrationError.noteNotFound }
        if let changes = try? await session.indexer.update([path]) { await session.apply(changes, fromSave: true) }
        return IntegrationNote(id: SpotlightIndex.identifier(notebookID: entry.id, path: path), notebookID: entry.id,
                               notebookName: entry.name, path: path.rawValue, title: title ?? path.stem,
                               snippet: String(body.prefix(200)), modified: Date())
    }

    /// Adds `text` at the end of the note (through its editor when it's open).
    public func append(_ text: String, toNote id: String) async throws {
        let (session, path) = try locate(id)
        let addition = text.trimmingCharacters(in: .newlines)
        guard !addition.isEmpty else { return }
        func appended(to existing: String) -> String {
            var result = existing
            if !result.isEmpty, !result.hasSuffix("\n") { result += "\n" }
            if !result.isEmpty { result += "\n" }
            return result + addition + "\n"
        }
        if let editor = session.openEditor(for: path) {
            editor.text = appended(to: editor.text)
            editor.flush()
        } else {
            let file = NoteFile(url: session.notebook.url(for: path))
            let snapshot = try file.read()
            _ = try file.write(appended(to: snapshot.text), replacing: snapshot)
            if let changes = try? await session.indexer.update([path]) { await session.apply(changes, fromSave: true) }
        }
    }

    // MARK: Helpers

    private var selectedEntry: Entry? { selectedID.flatMap { id in entries.first { $0.id == id } } }

    private func locate(_ id: String) throws -> (NotebookSession, NotebookPath) {
        guard let (notebookID, path) = SpotlightIndex.parse(id), let session = session(for: notebookID),
              FileManager.default.fileExists(atPath: session.notebook.url(for: path).path) else { throw IntegrationError.noteNotFound }
        return (session, path)
    }

    private func note(_ summary: NoteSummary, in entry: Entry) -> IntegrationNote {
        IntegrationNote(id: SpotlightIndex.identifier(notebookID: entry.id, path: summary.path), notebookID: entry.id,
                        notebookName: entry.name, path: summary.path.rawValue, title: summary.title,
                        snippet: summary.snippet, modified: summary.modified)
    }
}
