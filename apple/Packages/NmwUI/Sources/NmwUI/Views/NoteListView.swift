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
    @FocusState private var isSearchFocused: Bool
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #endif

    var body: some View {
        list
        .contextMenu(forSelectionType: NotebookPath.self) { paths in
            if paths.count == 1, let path = paths.first, let note = session.notes.first(where: { $0.path == path }) {
                menu(for: note)
            } else if paths.count > 1 {
                menu(forMany: Array(paths))
            }
        }
        .focused($isFocused)
        .themePage()
        #if os(macOS)
        .onDeleteCommand {
            if !session.selectedNotes.isEmpty { trash(Array(session.selectedNotes)) } else if let path = session.selection { trash(path) }
        }
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
        .searchFocused($isSearchFocused)
        .onChange(of: session.searchFocusRequest) { isSearchFocused = true }
        .navigationTitle(title)
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Picker("Sort By", selection: $session.sort) {
                        Label("Date Modified", systemImage: "clock").tag(NoteSort.modified)
                        Label("Date Created", systemImage: "calendar").tag(NoteSort.created)
                        Label("Title", systemImage: "textformat").tag(NoteSort.title)
                    }
                    #if os(iOS)
                    Divider()
                    Button("Select Notes", systemImage: "checkmark.circle") { editMode = .active }
                        .disabled(session.notes.isEmpty)
                    #endif
                } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
                #if os(iOS)
                if editMode.isEditing {
                    Button("Done") { endSelecting() }.fontWeight(.semibold)
                } else {
                    Button { newNote() } label: { Label("New Note", systemImage: "square.and.pencil") }
                }
                #else
                Button { newNote() } label: { Label("New Note", systemImage: "square.and.pencil") }
                #endif
            }
        }
        .namePrompt("Rename Note", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }),
                    text: $newName, actionTitle: "Rename", message: "Links to this note are updated.") {
            if let note = renaming { rename(note) }
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

    /// ⌘/⇧-click selects several notes on the Mac; on iOS only in Select mode,
    /// since a plain tap must keep pushing the editor.
    @ViewBuilder private var list: some View {
        #if os(iOS)
        if editMode.isEditing {
            List(selection: manySelection) { rows }
                .environment(\.editMode, $editMode)
                .toolbar { selectToolbar }
        } else {
            List(selection: $session.selection) { rows }
        }
        #else
        List(selection: manySelection) { rows }
        #endif
    }

    private var manySelection: Binding<Set<NotebookPath>> {
        Binding(
            get: { session.selectedNotes.isEmpty ? Set([session.selection].compactMap { $0 }) : session.selectedNotes },
            set: { new in
                if new.count > 1 {
                    session.selectedNotes = new
                } else {
                    session.selectedNotes = []
                    #if os(iOS)
                    // In Select mode a single checked row doesn't open the note.
                    if editMode.isEditing { session.selectedNotes = new; return }
                    #endif
                    session.selection = new.first
                }
            }
        )
    }

    @ViewBuilder private var rows: some View {
        // Rows are one height: a folder line is reserved on every row when any shows one.
        let showsFolders = session.notes.contains { subfolder(of: $0) != nil }
        ForEach(session.notes) { note in
            NoteRow(note: note, root: session.notebook.root, subfolder: subfolder(of: note), reservesFolderLine: showsFolders)
                .tag(note.path)
                .draggable(dragItem(for: note.path)) { dragPreview(for: note) }
                #if os(macOS)
                // macOS only: on iOS the gesture swallowed taps on the row's text.
                .simultaneousGesture(TapGesture().onEnded { isFocused = true })
                #endif
                #if os(iOS)
                .themeRow(selected: session.selection == note.path && !editMode.isEditing)
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

    /// Dragging a selected note takes the whole selection along.
    private func dragItem(for path: NotebookPath) -> NotebookDragItem {
        let many = session.selectedNotes.contains(path) ? session.notes.map(\.path).filter(session.selectedNotes.contains) : [path]
        return NotebookDragItem(notebook: session.notebook, paths: many)
    }

    private func dragPreview(for note: NoteSummary) -> some View {
        let count = session.selectedNotes.contains(note.path) ? session.selectedNotes.count : 1
        return Label(count > 1 ? "\(count) Notes" : note.title, systemImage: count > 1 ? "doc.on.doc" : "doc.text")
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
    }

    #if os(iOS)
    @ToolbarContentBuilder private var selectToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            let paths = Array(session.selectedNotes)
            Menu("Move To", systemImage: "folder") { moveTargets(for: paths) }
                .disabled(paths.isEmpty)
            Spacer()
            Button("Pin", systemImage: "pin") { run { try await session.setPinned(paths, true) }; endSelecting() }
                .disabled(paths.isEmpty)
            Spacer()
            Button("Trash", systemImage: "trash", role: .destructive) { trash(paths); endSelecting() }
                .disabled(paths.isEmpty)
        }
    }

    private func endSelecting() {
        editMode = .inactive
        session.selectedNotes = []
    }
    #endif

    /// The folders `paths` can move to: the notebook itself, then every folder.
    @ViewBuilder private func moveTargets(for paths: [NotebookPath]) -> some View {
        Button(session.name, systemImage: "books.vertical") { move(paths, to: nil) }
            .disabled(!paths.contains { session.canMove($0, toFolder: nil) })
        ForEach(Self.flatten(session.folders), id: \.path) { folder in
            Button(folder.path.rawValue, systemImage: "folder") { move(paths, to: folder.path) }
                .disabled(!paths.contains { session.canMove($0, toFolder: folder.path) })
        }
    }

    private func move(_ paths: [NotebookPath], to folder: NotebookPath?) {
        run {
            try await session.move(paths, toFolder: folder)
            #if os(iOS)
            endSelecting()
            #endif
        }
    }

    @ViewBuilder private func menu(forMany paths: [NotebookPath]) -> some View {
        let notes = session.notes.filter { paths.contains($0.path) }
        let allPinned = notes.allSatisfy(\.pinned)
        Button(allPinned ? "Unpin \(paths.count) Notes" : "Pin \(paths.count) Notes", systemImage: allPinned ? "pin.slash" : "pin") {
            run { try await session.setPinned(paths, !allPinned) }
        }
        Menu("Move To", systemImage: "folder") { moveTargets(for: paths) }
        #if os(macOS)
        Button("Show in Finder", systemImage: "finder") {
            NSWorkspace.shared.activateFileViewerSelecting(paths.map(session.notebook.url(for:)))
        }
        #endif
        Divider()
        Button("Move \(paths.count) Notes to Trash", systemImage: "trash", role: .destructive) { trash(paths) }
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

    /// The note's folder in lists that span folders (All Notes, Pinned, a tag);
    /// the notebook's name for notes at its root. A folder lists only its own notes.
    private func subfolder(of note: NoteSummary) -> String? {
        if case .folder = session.scope { return nil }
        return note.path.parent?.name ?? session.name
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
        Menu("Move To", systemImage: "folder") { moveTargets(for: [note.path]) }
        Button("Move to Notebook…", systemImage: "books.vertical") { requestMoveToNotebook(note.path) }
        #if os(macOS)
        ShowInFinderButton(url: session.notebook.url(for: note.path))
        #endif
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

    private func trash(_ paths: [NotebookPath]) {
        guard paths.count > 1 else { if let path = paths.first { trash(path) }; return }
        run { try await session.moveToTrash(paths) }
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
    /// Keep the folder line's space even without a folder, so rows line up.
    var reservesFolderLine = false

    /// Every row has the same lines (title, two of date and preview, maybe a
    /// folder), so the list is even whatever a note contains.
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if note.pinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.orange) }
                    Text(note.title).font(.headline).lineLimit(1)
                    Spacer(minLength: 4)
                    if note.tasksTotal > 0 {
                        // Checklist progress, e.g. "3/5".
                        Label("\(note.tasksDone)/\(note.tasksTotal)", systemImage: note.tasksDone == note.tasksTotal ? "checkmark.circle.fill" : "circle.dashed")
                            .labelStyle(.titleAndIcon)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(note.tasksDone == note.tasksTotal ? Palette.accentColor : .secondary)
                            .fixedSize()
                    }
                }
                let date = Text(note.modified, format: .dateTime.day().month(.abbreviated).year()).foregroundStyle(.primary)
                let snippet = Text(note.snippet.isEmpty ? "No additional text" : note.snippet).foregroundStyle(.secondary)
                Text("\(date)  \(snippet)")
                    .font(.subheadline)
                    .lineLimit(2, reservesSpace: true)
                if subfolder != nil || reservesFolderLine {
                    Label(subfolder ?? " ", systemImage: "folder").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        .opacity(subfolder == nil ? 0 : 1)
                }
            }
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
