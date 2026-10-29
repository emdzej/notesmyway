//
//  NotebookView.swift
//  NmwUI
//
//  The three columns (spec §5): sidebar (notebooks, All / Pinned, folders,
//  tags), the note list, and the editor. iPhone collapses them to a stack.
//

import NmwCore
import SwiftUI

struct NotebookView: View {
    @Bindable var session: NotebookSession
    let library: Library
    let addNotebook: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var missingNote: NotebookPath?

    var body: some View {
        NavigationSplitView {
            SidebarView(session: session, library: library, addNotebook: addNotebook)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } content: {
            NoteListView(session: session)
                .navigationSplitViewColumnWidth(min: 240, ideal: 300)
        } detail: {
            detail
        }
        .focusedSceneValue(\.notebookSession, session)
        .overlay(alignment: .bottom) {
            if let fix = session.linkFix { LinkFixBanner(session: session, fix: fix).padding() }
        }
        .onChange(of: session.selection) { _, new in session.closeEditors(except: new) }
        .sheet(isPresented: $session.isShowingSwitcher) {
            NotePicker(prompt: "Open note…", notes: (try? session.index.notes(sortedBy: .modified)) ?? []) { note in
                session.isShowingSwitcher = false
                session.scope = .all
                session.selection = note.path
            }
        }
        .alert("“\(missingNote?.stem ?? "")” doesn’t exist yet", isPresented: Binding(get: { missingNote != nil }, set: { if !$0 { missingNote = nil } })) {
            Button("Create Note") {
                if let path = missingNote { Task { try? await session.createMissingNote(at: path) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The link points to \(missingNote?.rawValue ?? ""). Create it there?")
        }
    }

    @ViewBuilder private var detail: some View {
        if let path = session.selection {
            NoteEditorView(
                model: session.editor(for: path),
                root: session.notebook.root,
                previews: session.previews,
                attachments: session.config.attachments,
                version: session.contentVersion,
                linkableNotes: { (try? session.index.notes(sortedBy: .title)) ?? [] },
                onLink: handle,
                onStoredFiles: { _ in },
                backlinks: { (try? session.index.backlinks(to: path)) ?? [] },
                onOpenNote: { session.selection = $0 }
            )
            .id(path)
            #if os(macOS)
            .navigationTitle(session.notes.first { $0.path == path }?.title ?? path.stem)
            #else
            // The note's own first line is its title; don't repeat it above the text.
            .navigationTitle("")
            .toolbarTitleDisplayMode(.inline)
            #endif
        } else {
            ContentUnavailableView("No Note Selected", systemImage: "note.text",
                                   description: Text("Pick a note, or press ⌘N to start one."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { WelcomeBackground() }
        }
    }

    private func handle(_ action: LinkAction) {
        switch action {
        case .note(let path):
            if FileManager.default.fileExists(atPath: session.notebook.url(for: path).path) {
                session.selection = path
            } else {
                missingNote = path
            }
        case .standalone(let url): library.open(file: url)
        case .file(let url): openURL(url)
        case .external(let url): openURL(url)
        case .none: break
        }
    }
}

struct LinkFixBanner: View {
    let session: NotebookSession
    let fix: LinkFixSummary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "link")
            Text(message).font(.callout)
            if !fix.notes.isEmpty || fix.move != nil { Button("Undo") { Task { await session.undoLinkFix() } } }
            Button { session.linkFix = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .task(id: fix.id) {
            try? await Task.sleep(for: .seconds(8))
            if session.linkFix?.id == fix.id { session.linkFix = nil }
        }
    }

    private var message: String {
        var parts: [String] = []
        if let move = fix.move {
            parts.append(move.from.parent == move.to.parent ? "Renamed to “\(move.to.stem)”" : "Moved to \(move.to.parent?.rawValue ?? session.name)")
        }
        if !fix.notes.isEmpty {
            parts.append(fix.notes.count == 1 ? "updated links in 1 note" : "updated links in \(fix.notes.count) notes")
        }
        if !fix.skipped.isEmpty { parts.append("\(fix.skipped.count) changed meanwhile, left as is") }
        let text = parts.joined(separator: " · ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}

struct SidebarView: View {
    @Bindable var session: NotebookSession
    let library: Library
    let addNotebook: () -> Void
    @State private var renamingFolder: NotebookPath?
    @State private var folderName = ""
    @State private var errorMessage: String?
    @State private var trashingFolder: NotebookPath?
    @AppStorage(SidebarStyle.key) private var sidebarStyle = SidebarStyle.system

    var body: some View {
        List(selection: Binding<NotebookSession.Scope?>(get: { session.scope }, set: { if let s = $0 { session.scope = s } })) {
            Section {
                Label("All Notes", systemImage: "note.text").tag(NotebookSession.Scope.all)
                Label("Pinned", systemImage: "pin").tag(NotebookSession.Scope.pinned)
            }
            Section("Folders") {
                // The notebook's own folder is the parent of its subfolders.
                if session.folders.isEmpty {
                    rootRow
                } else {
                    DisclosureGroup(isExpanded: Binding(get: { !session.isRootCollapsed }, set: { session.isRootCollapsed = !$0 })) {
                        FolderRows(nodes: session.folders, session: session, row: folderRow)
                    } label: {
                        rootRow
                    }
                }
            }
            if !session.tags.isEmpty {
                Section("Tags") {
                    ForEach(session.tags, id: \.tag) { tag in
                        HStack {
                            Label(tag.tag, systemImage: "number")
                            Spacer()
                            Text("\(tag.count)").foregroundStyle(.secondary).font(.caption)
                        }
                        .tag(NotebookSession.Scope.tag(tag.tag))
                    }
                }
            }
        }
        .safeAreaInset(edge: .top) { NotebookMenu(session: session, library: library, addNotebook: addNotebook).padding(.horizontal, 10).padding(.vertical, 6) }
        .overlay(alignment: .bottom) {
            if session.isIndexing { ProgressView("Indexing…").controlSize(.small).padding(8) }
        }
        .sidebarStyle(sidebarStyle)
        #if os(macOS)
        .onDeleteCommand {
            if case .folder(let folder?) = session.scope { trashingFolder = folder }
        }
        #endif
        .confirmationDialog("Move “\(trashingFolder?.name ?? "")” to the Trash?", isPresented: Binding(get: { trashingFolder != nil }, set: { if !$0 { trashingFolder = nil } })) {
            Button("Move to Trash", role: .destructive) {
                if let folder = trashingFolder { run { try await session.moveFolderToTrash(folder) } }
            }
        } message: {
            Text("The folder and the notes in it go to the notebook’s trash (.nmw/trash), where they’re kept for 30 days.")
        }
        .alert("Rename Folder", isPresented: Binding(get: { renamingFolder != nil }, set: { if !$0 { renamingFolder = nil } })) {
            TextField("Name", text: $folderName)
            Button("Rename") {
                if let folder = renamingFolder {
                    let name = folderName
                    run { try await session.renameFolder(folder, to: name) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Links to notes inside it are updated.") }
        .alert("Couldn’t Complete", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private var rootRow: some View {
        Label(session.name, systemImage: "folder")
            .tag(NotebookSession.Scope.folder(nil))
            .contextMenu { Button("New Folder") { newFolder(in: nil) } }
    }

    private func folderRow(_ node: FolderNode) -> AnyView {
        AnyView(
            Label(node.name, systemImage: "folder")
                .tag(NotebookSession.Scope.folder(node.path))
                .contextMenu {
                    Button("New Folder") { newFolder(in: node.path) }
                    Button("Rename…") { folderName = node.name; renamingFolder = node.path }
                    Divider()
                    Button("Move to Trash…", role: .destructive) { trashingFolder = node.path }
                }
        )
    }

    private func newFolder(in parent: NotebookPath?) {
        do {
            let folder = try session.createFolder(in: parent)
            session.scope = .folder(folder)
            folderName = folder.name
            renamingFolder = folder
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        Task { @MainActor in
            do { try await action() } catch { errorMessage = error.localizedDescription }
        }
    }
}

/// The folder tree: every level starts expanded, with its disclosure arrow visible.
struct FolderRows: View {
    let nodes: [FolderNode]
    let session: NotebookSession
    let row: (FolderNode) -> AnyView

    var body: some View {
        ForEach(nodes) { node in
            if let children = node.children {
                DisclosureGroup(isExpanded: expanded(node.path)) {
                    AnyView(FolderRows(nodes: children, session: session, row: row))
                } label: {
                    row(node)
                }
            } else {
                row(node)
            }
        }
    }

    private func expanded(_ path: NotebookPath) -> Binding<Bool> {
        Binding(
            get: { !session.collapsedFolders.contains(path) },
            set: { open in
                if open { session.collapsedFolders.remove(path) } else { session.collapsedFolders.insert(path) }
            }
        )
    }
}

/// Switch notebooks, add one, or remove the current one from the library.
struct NotebookMenu: View {
    let session: NotebookSession
    let library: Library
    let addNotebook: () -> Void
    @State private var showingSettings = false

    var body: some View {
        Menu {
            ForEach(library.entries) { entry in
                Button { library.selectedID = entry.id } label: {
                    if entry.id == library.selectedID { Label(entry.name, systemImage: "checkmark") } else { Text(entry.name) }
                }
            }
            Divider()
            Button("Add Notebook…", action: addNotebook)
            #if !os(macOS)
            Button("Settings…") { showingSettings = true }
            #endif
            if let current = library.entries.first(where: { $0.id == library.selectedID }) {
                Button("Remove “\(current.name)” from Notes my Way") { library.remove(current) }
            }
        } label: {
            Label(session.name, systemImage: "books.vertical").font(.headline)
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: .infinity, alignment: .leading)
        #if !os(macOS)
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                List {
                    NavigationLink("General") { GeneralSettingsForm().navigationTitle("General") }
                    NavigationLink("“\(session.name)” Notebook") {
                        NotebookSettingsForm(session: session).navigationTitle(session.name)
                    }
                }
                .navigationTitle("Settings")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingSettings = false } } }
            }
        }
        #endif
    }
}

extension View {
    /// "My Way": the icon's gradient behind the sidebar, with light text on it.
    @ViewBuilder func sidebarStyle(_ style: SidebarStyle) -> some View {
        switch style {
        case .system:
            self
        case .myWay:
            self
                .scrollContentBackground(.hidden)
                .background {
                    LinearGradient(colors: [Palette.sidebarTop, Palette.sidebarBottom], startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                }
                .environment(\.colorScheme, .dark)
                .tint(.white)
        }
    }
}
