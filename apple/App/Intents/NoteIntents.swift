//
//  NoteIntents.swift
//  nmw
//
//  Shortcuts actions: create, append to, open, search and read notes.
//

import AppIntents
import NmwUI

struct CreateNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Note"
    static let description = IntentDescription("Creates a Markdown note in a notebook.")

    @Parameter(title: "Title") var noteTitle: String?
    @Parameter(title: "Text", inputOptions: String.IntentInputOptions(multiline: true)) var body: String?
    @Parameter(title: "Notebook", description: "The notebook selected in the app if empty.") var notebook: NotebookEntity?
    @Parameter(title: "Folder", description: "A folder in the notebook, such as Projects/2026.") var folder: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Create note \(\.$noteTitle) with \(\.$body)") {
            \.$notebook
            \.$folder
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<NoteEntity> {
        let note = try await Library.shared.createNote(notebookID: notebook?.id, folder: folder, title: noteTitle, body: body ?? "")
        return .result(value: NoteEntity(note))
    }
}

struct AppendToNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Append to Note"
    static let description = IntentDescription("Adds text at the end of a note.")

    @Parameter(title: "Text", inputOptions: String.IntentInputOptions(multiline: true)) var text: String
    @Parameter(title: "Note") var note: NoteEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Append \(\.$text) to \(\.$note)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await Library.shared.append(text, toNote: note.id)
        return .result()
    }
}

struct OpenNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Note"
    static let description = IntentDescription("Opens a note in Notes my Way.")
    static let openAppWhenRun = true

    @Parameter(title: "Note") var note: NoteEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$note)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let parts = note.id.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, Library.shared.open(notebookID: parts[0], path: parts[1]) else {
            throw IntegrationError.noteNotFound
        }
        return .result()
    }
}

struct SearchNotesIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Notes"
    static let description = IntentDescription("Finds notes by their text, with tag: and path: filters like the app's search.")

    @Parameter(title: "Search") var query: String
    @Parameter(title: "Limit", default: 20, inclusiveRange: (1, 100)) var limit: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Search notes for \(\.$query)") { \.$limit }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[NoteEntity]> {
        .result(value: Library.shared.searchNotes(query, limit: limit).map(NoteEntity.init))
    }
}

struct GetNoteTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Note Text"
    static let description = IntentDescription("Returns a note's Markdown.")

    @Parameter(title: "Note") var note: NoteEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Get the text of \(\.$note)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: try Library.shared.text(ofNote: note.id))
    }
}

struct NmwShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CreateNoteIntent(), phrases: [
            "Create a note in \(.applicationName)",
            "New \(.applicationName) note",
        ], shortTitle: "Create Note", systemImageName: "square.and.pencil")
        AppShortcut(intent: AppendToNoteIntent(), phrases: [
            "Append to a note in \(.applicationName)",
        ], shortTitle: "Append to Note", systemImageName: "text.append")
        AppShortcut(intent: OpenNoteIntent(), phrases: [
            "Open a note in \(.applicationName)",
        ], shortTitle: "Open Note", systemImageName: "note.text")
        AppShortcut(intent: SearchNotesIntent(), phrases: [
            "Search \(.applicationName)",
        ], shortTitle: "Search Notes", systemImageName: "magnifyingglass")
    }
}
