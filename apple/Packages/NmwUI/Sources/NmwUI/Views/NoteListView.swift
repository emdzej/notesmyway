//
//  NoteListView.swift
//  NmwUI
//
//  The middle column: notes in the current scope or search, pinned first,
//  with title, date, a two-line snippet and the first image.
//

import NmwCore
import SwiftUI

struct NoteListView: View {
    @Bindable var session: NotebookSession
    @State private var renaming: NoteSummary?
    @State private var newName = ""
    @State private var errorMessage: String?
    /// A click selects a row but doesn't focus the list once the editor had
    /// focus, so the selection stayed gray; clicks focus it explicitly.
    @FocusState private var isFocused: Bool

    var body: some View {
        List(selection: $session.selection) {
            ForEach(session.notes) { note in
                NoteRow(note: note, root: session.notebook.root, subfolder: subfolder(of: note))
                    .tag(note.path)
                    #if os(macOS)
                    // macOS only: on iOS the gesture swallowed taps on the row's text.
                    .simultaneousGesture(TapGesture().onEnded { isFocused = true })
                    #endif
                    .contextMenu { menu(for: note) }
                    #if os(iOS)
                    .swipeActions(edge: .trailing) {
                        // The app-wide accent tint would otherwise override the destructive red.
                        Button("Trash", systemImage: "trash", role: .destructive) { trash(note.path) }
                            .tint(.red)
                    }
                    .swipeActions(edge: .leading) {
                        Button(note.pinned ? "Unpin" : "Pin", systemImage: note.pinned ? "pin.slash" : "pin") {
                            run { try await session.setPinned(note.path, !note.pinned) }
                        }
                        .tint(.orange)
                    }
                    #endif
            }
        }
        .focused($isFocused)
        #if os(macOS)
        .onDeleteCommand { if let path = session.selection { trash(path) } }
        #endif
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

    /// Where a note sits below the selected folder ("2026/Q4"), nil when directly in it.
    private func subfolder(of note: NoteSummary) -> String? {
        guard case .folder(let folder?) = session.scope, let parent = note.path.parent, parent != folder,
              parent.isInside(folder) else { return nil }
        return String(parent.rawValue.dropFirst(folder.rawValue.count + 1))
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
        Button("Move to Trash", role: .destructive) { trash(note.path) }
    }

    /// Trashes a note; if it was selected, the next one in the list (or the previous) is selected.
    private func trash(_ path: NotebookPath) {
        let notes = session.notes
        let next: NotebookPath? = notes.firstIndex { $0.path == path }.flatMap { i in
            notes.indices.contains(i + 1) ? notes[i + 1].path : (i > 0 ? notes[i - 1].path : nil)
        }
        let wasSelected = session.selection == path
        run {
            try await session.moveToTrash(path)
            if wasSelected { session.selection = next }
        }
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
    var subfolder: String? = nil

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
                if let subfolder {
                    Label(subfolder, systemImage: "folder").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let thumbnail { thumbnail.resizable().scaledToFill().frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 6)) }
        }
        .padding(.vertical, 4)
    }

    private var thumbnail: Image? {
        guard let source = note.firstImage,
              case .file(let url, _)? = LinkTarget.resolve(source, from: note.path.url(in: root), root: root),
              let image = ImageCache.shared.image(at: url, maxPixelSize: 200) else { return nil }
        #if os(macOS)
        return Image(nsImage: image)
        #else
        return Image(uiImage: image)
        #endif
    }
}
