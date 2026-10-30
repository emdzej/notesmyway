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
    let library: Library
    @State private var renaming: NoteSummary?
    /// Move to Notebook…: the note whose target notebook is being picked.
    @State private var movingToNotebook: NotebookPath?
    /// Move to Notebook… confirmed only after warning about links that will break.
    @State private var pendingMove: PendingNotebookMove?
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
                    .themeRow(selected: session.selection == note.path)
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
        .themePage()
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
                        Label("Date Modified", systemImage: "clock").tag(NoteSort.modified)
                        Label("Date Created", systemImage: "calendar").tag(NoteSort.created)
                        Label("Title", systemImage: "textformat").tag(NoteSort.title)
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
        .confirmationDialog("Move “\(movingToNotebook?.stem ?? "")” to Notebook", isPresented: Binding(get: { movingToNotebook != nil }, set: { if !$0 { movingToNotebook = nil } }), titleVisibility: .visible) {
            ForEach(otherNotebooks) { entry in
                Button(entry.name) { if let path = movingToNotebook { prepareMove(path, to: entry) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The note and the attachments it uses move to the other notebook.")
        }
        .alert("Links Will Break", isPresented: Binding(get: { pendingMove != nil }, set: { if !$0 { pendingMove = nil } }), presenting: pendingMove) { move in
            Button("Move Anyway", role: .destructive) { perform(move) }
            Button("Cancel", role: .cancel) {}
        } message: { move in
            Text(move.backlinks == 1
                 ? "1 note in “\(session.name)” links to “\(move.path.stem)”. That link will break."
                 : "\(move.backlinks) notes in “\(session.name)” link to “\(move.path.stem)”. Their links will break.")
        }
        .onChange(of: session.renameRequest) { _, path in
            guard let path else { return }
            session.renameRequest = nil
            if let note = session.notes.first(where: { $0.path == path }) ?? (try? session.index.note(at: path)) {
                newName = note.path.stem
                renaming = note
            }
        }
        .onChange(of: session.moveToNotebookRequest) { _, path in
            guard let path else { return }
            session.moveToNotebookRequest = nil
            requestMoveToNotebook(path)
        }
        .alert("Couldn’t Complete", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private var otherNotebooks: [Library.Entry] {
        library.entries.filter { $0.id != session.notebook.localID }
    }

    private func requestMoveToNotebook(_ path: NotebookPath) {
        if otherNotebooks.isEmpty {
            errorMessage = "Add another notebook first (notebook menu › Add Notebook…)."
        } else {
            movingToNotebook = path
        }
    }

    private func prepareMove(_ path: NotebookPath, to entry: Library.Entry) {
        let backlinks = ((try? session.index.backlinks(to: path)) ?? []).filter { $0.path != path }.count
        let move = PendingNotebookMove(path: path, entryID: entry.id, backlinks: backlinks)
        if backlinks > 0 { pendingMove = move } else { perform(move) }
    }

    private func perform(_ move: PendingNotebookMove) {
        run { try await library.move(move.path, from: session, toNotebook: move.entryID) }
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
        case .trash: "Recently Deleted"
        }
    }

    @ViewBuilder private func menu(for note: NoteSummary) -> some View {
        Button(note.pinned ? "Unpin" : "Pin", systemImage: note.pinned ? "pin.slash" : "pin") { run { try await session.setPinned(note.path, !note.pinned) } }
        Button("Share…", systemImage: "square.and.arrow.up") { share(note) }
        Button("Rename…", systemImage: "pencil") { newName = note.path.stem; renaming = note }
        Menu("Move To", systemImage: "folder") {
            Button(session.name, systemImage: "books.vertical") { run { try await session.move(note.path, toFolder: nil) } }
            ForEach(Self.flatten(session.folders), id: \.path) { folder in
                Button(folder.path.rawValue, systemImage: "folder") { run { try await session.move(note.path, toFolder: folder.path) } }
            }
        }
        Button("Move to Notebook…", systemImage: "books.vertical") { requestMoveToNotebook(note.path) }
        Divider()
        Button("Move to Trash", systemImage: "trash", role: .destructive) { trash(note.path) }
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

    /// Shares a note from the list: the open editor's text, else the file's.
    private func share(_ note: NoteSummary) {
        let url = session.notebook.url(for: note.path)
        let text = session.openEditorText(for: note.path) ?? (try? NoteFile(url: url).read().text)
        guard let text else { return }
        let context = NoteContext(noteURL: url, root: session.notebook.root, previews: session.previews,
                                  attachments: session.config.attachments)
        NoteSharing.share(NoteExporter(markdown: text, title: note.title, context: context))
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
                if note.tasksTotal > 0 {
                    // Checklist progress, e.g. "3/5".
                    Label("\(note.tasksDone)/\(note.tasksTotal)", systemImage: note.tasksDone == note.tasksTotal ? "checkmark.circle.fill" : "circle.dashed")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(note.tasksDone == note.tasksTotal ? Palette.accentColor : .secondary)
                }
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

struct PendingNotebookMove: Identifiable {
    var id: String { path.rawValue + "→" + entryID }
    let path: NotebookPath
    let entryID: String
    let backlinks: Int
}
