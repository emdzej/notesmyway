//
//  NoteEntities.swift
//  nmw
//
//  Notes and notebooks for Shortcuts / Siri. Queries go through the app's
//  library (intents run in the app's process, with its folder access).
//

import AppIntents
import NmwUI

struct NoteEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Note"
    static let defaultQuery = NoteQuery()

    /// `<notebook id>/<path>`.
    let id: String
    @Property(title: "Title") var title: String
    @Property(title: "Notebook") var notebook: String
    @Property(title: "Path") var path: String
    @Property(title: "Modified") var modified: Date
    let snippet: String

    init(_ note: IntegrationNote) {
        id = note.id
        snippet = note.snippet
        title = note.title
        notebook = note.notebookName
        path = note.path
        modified = note.modified
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(notebook) · \(path)", image: .init(systemName: "note.text"))
    }
}

struct NoteQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [NoteEntity.ID]) async throws -> [NoteEntity] {
        Library.shared.notes(withIDs: identifiers).map(NoteEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [NoteEntity] {
        Library.shared.searchNotes(string).map(NoteEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [NoteEntity] {
        Library.shared.recentNotes(limit: 12).map(NoteEntity.init)
    }
}

struct NotebookEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Notebook"
    static let defaultQuery = NotebookQuery()

    let id: String
    @Property(title: "Name") var name: String

    init(_ notebook: IntegrationNotebook) {
        id = notebook.id
        name = notebook.name
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: "books.vertical"))
    }
}

struct NotebookQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [NotebookEntity.ID]) async throws -> [NotebookEntity] {
        Library.shared.integrationNotebooks.filter { identifiers.contains($0.id) }.map(NotebookEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [NotebookEntity] {
        Library.shared.integrationNotebooks.map(NotebookEntity.init)
    }
}
