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
    /// iPhone: which column shows (the sidebar unless a DEBUG launch option says otherwise).
    @State private var compactColumn: NavigationSplitViewColumn = Self.launchCompactColumn
    @State private var columnVisibility: NavigationSplitViewVisibility = Self.launchColumnVisibility

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $compactColumn) {
            SidebarView(session: session, library: library, addNotebook: addNotebook)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } content: {
            Group {
                if session.scope == .trash { TrashListView(session: session) } else { NoteListView(session: session, library: library) }
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 300)
        } detail: {
            detail
        }
        .focusedSceneValue(\.notebookSession, session)
        #if DEBUG
        .task { await applyLaunchOptions() }
        #endif
        .overlay(alignment: .bottom) {
            if let fix = session.linkFix { LinkFixBanner(session: session, fix: fix).padding() }
        }
        .onChange(of: session.selection) { _, new in session.closeEditors(except: new) }
        .sheet(isPresented: $session.isShowingPalette) {
            CommandPalette(session: session, library: library)
        }
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

    private static var launchCompactColumn: NavigationSplitViewColumn {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "NmwCompactColumn") {
        case "content": return .content
        case "detail": return .detail
        default: return .sidebar
        }
        #else
        return .sidebar
        #endif
    }

    private static var launchColumnVisibility: NavigationSplitViewVisibility {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "NmwColumnVisibility") == "doubleColumn" { return .doubleColumn }
        #endif
        return .automatic
    }

    #if DEBUG
    /// Screenshots: `-NmwScope all|pinned|folder:<path>|tag:<tag>` and
    /// `-NmwOpenNote <path in the notebook>`, applied once indexing is done.
    /// (Settings such as `-nmw.theme paper` or `-nmw.showsInspector YES`
    /// work as launch arguments already.)
    private func applyLaunchOptions() async {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: "NmwScope") != nil || defaults.string(forKey: "NmwOpenNote") != nil else { return }
        for _ in 0..<50 where session.isIndexing || session.notes.isEmpty {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if let scope = defaults.string(forKey: "NmwScope") {
            if scope == "pinned" { session.scope = .pinned }
            else if scope.hasPrefix("folder:") { session.scope = .folder(NotebookPath(String(scope.dropFirst(7)))) }
            else if scope.hasPrefix("tag:") { session.scope = .tag(String(scope.dropFirst(4))) }
            else { session.scope = .all }
        }
        if let note = defaults.string(forKey: "NmwOpenNote") { session.selection = NotebookPath(note) }
    }
    #endif

    @ViewBuilder private var detail: some View {
        if session.scope == .trash {
            TrashDetail(session: session)
        } else if let path = session.selection {
            let model = session.editor(for: path)
            NoteEditorView(
                model: model,
                root: session.notebook.root,
                previews: session.previews,
                attachments: session.config.attachments,
                version: session.contentVersion,
                linkableNotes: { (try? session.index.notes(sortedBy: .title)) ?? [] },
                onLink: handle,
                onStoredFiles: { _ in },
                backlinks: { (try? session.index.backlinks(to: path)) ?? [] },
                onOpenNote: { session.selection = $0 },
                onController: { session.activeController = $0 }
            )
            // The model, not the path: a rename (e.g. after the heading) keeps the editor.
            .id(model.documentID)
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
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// iPhone: going back clears the list's selection; the scope stays, and
    /// tapping the same row again pushes the note list again.
    @State private var compactSelection: NotebookSession.Scope?
    #endif

    private var selection: Binding<NotebookSession.Scope?> {
        #if os(iOS)
        if sizeClass == .compact {
            return Binding(get: { compactSelection }, set: { value in
                compactSelection = value
                if let value { session.scope = value }
            })
        }
        #endif
        return Binding(get: { session.scope }, set: { if let s = $0 { session.scope = s } })
    }

    var body: some View {
        List(selection: selection) {
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
            if !session.trashItems.isEmpty || session.scope == .trash {
                Section {
                    Label("Recently Deleted", systemImage: "trash")
                        .badge(session.trashItems.count)
                        .tag(NotebookSession.Scope.trash)
                }
            }
        }
        #if os(macOS)
        .safeAreaInset(edge: .top) { NotebookMenu(session: session, library: library, addNotebook: addNotebook).padding(.horizontal, 10).padding(.vertical, 6) }
        #endif
        .overlay(alignment: .bottom) {
            if session.isIndexing { ProgressView("Indexing…").controlSize(.small).padding(8) }
        }
        .sidebarStyle(sidebarStyle)
        #if os(iOS)
        // The notebook menu sits in the navigation bar, not in a row of its own below an empty title.
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NotebookMenu(session: session, library: library, addNotebook: addNotebook)
                    .fixedSize()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { session.isShowingSettings = true } label: { Label("Settings", systemImage: "gearshape") }
            }
        }
        .sheet(isPresented: $session.isShowingSettings) { MobileSettings(session: session) }
        #endif
        #if os(macOS)
        .onDeleteCommand {
            if case .folder(let folder?) = session.scope { trashingFolder = folder }
        }
        #endif
        .confirmationDialog("Move “\(trashingFolder?.name ?? "")” to Recently Deleted?", isPresented: Binding(get: { trashingFolder != nil }, set: { if !$0 { trashingFolder = nil } })) {
            Button("Move to Trash", role: .destructive) {
                if let folder = trashingFolder { run { try await session.moveFolderToTrash(folder) } }
            }
        } message: {
            Text("The folder and the notes in it go to Recently Deleted (.nmw/trash), where they’re kept for 30 days and can be restored.")
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

    var body: some View {
        Menu {
            ForEach(library.entries) { entry in
                Button { library.selectedID = entry.id } label: {
                    if entry.id == library.selectedID { Label(entry.name, systemImage: "checkmark") } else { Text(entry.name) }
                }
            }
            Divider()
            Button("Add Notebook…", action: addNotebook)
            #if os(macOS)
            // iPhone / iPad: ⇧⌘P with a keyboard only; without one the buttons are quicker.
            Button("Command Palette…", systemImage: "command") { session.isShowingPalette = true }
            #endif
            #if !os(macOS)
            Button("Settings…") { session.isShowingSettings = true }
            #endif
            if let current = library.entries.first(where: { $0.id == library.selectedID }) {
                Button("Remove “\(current.name)” from Notes my Way") { library.remove(current) }
            }
        } label: {
            // Not a Label: toolbars (iOS) would show only its icon.
            HStack(spacing: 6) {
                Image(systemName: "books.vertical")
                Text(session.name)
                #if os(iOS)
                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                #endif
            }
            .font(.headline)
            .padding(.horizontal, 4)
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if os(iOS)
/// Settings on iPhone and iPad: app-wide ones and this notebook's.
struct MobileSettings: View {
    let session: NotebookSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                NavigationLink { GeneralSettingsForm().navigationTitle("General") } label: {
                    Label("General", systemImage: "gearshape")
                }
                NavigationLink { NotebookSettingsForm(session: session).navigationTitle(session.name) } label: {
                    Label("“\(session.name)” Notebook", systemImage: "books.vertical")
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
#endif

extension View {
    /// "My Way": the icon's gradient behind the sidebar, with light text on it.
    @ViewBuilder func sidebarStyle(_ style: SidebarStyle) -> some View {
        switch style {
        case .system:
            #if os(iOS)
            // On iPhone and iPad the sidebar is a whole screen: the welcome watermark fills it.
            self
                .scrollContentBackground(.hidden)
                .background {
                    ZStack {
                        Color(uiColor: .systemGroupedBackground)
                        WelcomeBackground()
                    }
                    .ignoresSafeArea()
                }
            #else
            self
            #endif
        case .myWay:
            self
                .scrollContentBackground(.hidden)
                .background {
                    ZStack {
                        LinearGradient(colors: [Palette.sidebarTop, Palette.sidebarBottom], startPoint: .top, endPoint: .bottom)
                        #if os(iOS)
                        WelcomeBackground(tint: .white, glow: false)
                        #endif
                    }
                    .ignoresSafeArea()
                }
                .environment(\.colorScheme, .dark)
                .tint(.white)
        }
    }
}
