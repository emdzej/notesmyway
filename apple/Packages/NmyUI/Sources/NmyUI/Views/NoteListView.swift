//
//  NoteListView.swift
//  NmyUI
//
//  The middle column: notes in the current scope or search, pinned first,
//  with title, date, a two-line snippet and the first image.
//

import NmyCore
import SwiftUI

struct NoteListView: View {
    @Bindable var session: NotebookSession
    @State private var renaming: NoteSummary?
    @State private var newName = ""
    @State private var errorMessage: String?

    var body: some View {
        List(selection: $session.selection) {
            ForEach(session.notes) { note in
                NoteRow(note: note, root: session.notebook.root)
                    .tag(note.path)
                    .contextMenu { menu(for: note) }
            }
        }
        .overlay {
            if session.notes.isEmpty, !session.isIndexing {
                if session.searchText.isEmpty {
                    ContentUnavailableView("No Notes", systemImage: "note.text", description: Text("Press ⌘N to create one."))
                } else {
                    ContentUnavailableView.search(text: session.searchText)
                }
            }
        }
        .searchable(text: $session.searchText, prompt: "Search (tag:, path:)")
        .navigationTitle(title)
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Picker("Sort By", selection: $session.sort) {
                        Text("Date Modified").tag(NoteSort.modified)
                        Text("Date Created").tag(NoteSort.created)
                        Text("Title").tag(NoteSort.title)
                    }
                } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
                Button { newNote() } label: { Label("New Note", systemImage: "square.and.pencil") }
            }
        }
        .alert("Rename Note", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") { if let note = renaming { rename(note) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Links to this note are updated.")
        }
        .alert("Couldn’t Complete", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private var title: String {
        switch session.scope {
        case .all: "All Notes"
        case .pinned: "Pinned"
        case .folder(let folder): folder?.name ?? session.name
        case .tag(let tag): "#\(tag)"
        }
    }

    @ViewBuilder private func menu(for note: NoteSummary) -> some View {
        Button(note.pinned ? "Unpin" : "Pin") { run { try await session.setPinned(note.path, !note.pinned) } }
        Button("Rename…") { newName = note.path.stem; renaming = note }
        Menu("Move To") {
            Button(session.name) { run { try await session.move(note.path, toFolder: nil) } }
            ForEach(Self.flatten(session.folders), id: \.path) { folder in
                Button(folder.path.rawValue) { run { try await session.move(note.path, toFolder: folder.path) } }
            }
        }
        Divider()
        Button("Move to Trash", role: .destructive) { run { try await session.moveToTrash(note.path) } }
    }

    static func flatten(_ nodes: [FolderNode]) -> [FolderNode] {
        nodes.flatMap { [$0] + flatten($0.children ?? []) }
    }

    func newNote() {
        let folder: NotebookPath? = if case .folder(let f) = session.scope { f } else { nil }
        run { try await session.createNote(in: folder) }
    }

    private func rename(_ note: NoteSummary) {
        let name = newName
        run { try await session.rename(note.path, to: name) }
    }

    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        Task { @MainActor in
            do { try await action() } catch { errorMessage = error.localizedDescription }
        }
    }
}

struct NoteRow: View {
    let note: NoteSummary
    let root: URL

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if note.pinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.orange) }
                    Text(note.title).font(.headline).lineLimit(1)
                }
                let date = Text(note.modified, format: .dateTime.day().month(.abbreviated).year()).foregroundStyle(.primary)
                let snippet = Text(note.snippet.isEmpty ? "No additional text" : note.snippet).foregroundStyle(.secondary)
                Text("\(date)  \(snippet)")
                    .font(.subheadline)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if let thumbnail { thumbnail.resizable().scaledToFill().frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 6)) }
        }
        .padding(.vertical, 4)
    }

    private var thumbnail: Image? {
        guard let source = note.firstImage,
              case .file(let url, _)? = LinkTarget.resolve(source, from: note.path.url(in: root), root: root),
              let image = ImageCache.shared.image(at: url) else { return nil }
        #if os(macOS)
        return Image(nsImage: image)
        #else
        return Image(uiImage: image)
        #endif
    }
}
