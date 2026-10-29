//
//  NotebookView.swift
//  NmyUI
//
//  The three columns (spec §5): sidebar (notebooks, All / Pinned, folders,
//  tags), the note list, and the editor. iPhone collapses them to a stack.
//

import NmyCore
import SwiftUI

struct NotebookView: View {
    @Bindable var session: NotebookSession
    let library: Library
    let addNotebook: () -> Void
    @Environment(\.openURL) private var openURL

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
    }

    @ViewBuilder private var detail: some View {
        if let path = session.selection {
            NoteEditorView(
                model: session.editor(for: path),
                root: session.notebook.root,
                previews: session.previews,
                version: session.contentVersion,
                linkableNotes: { (try? session.index.notes(sortedBy: .title)) ?? [] },
                onLink: handle,
                onStoredFiles: { _ in }
            )
            .id(path)
            .navigationTitle(session.notes.first { $0.path == path }?.title ?? path.stem)
        } else {
            ContentUnavailableView("No Note Selected", systemImage: "note.text",
                                   description: Text("Pick a note, or press ⌘N to start one."))
        }
    }

    private func handle(_ action: LinkAction) {
        switch action {
        case .note(let path):
            if FileManager.default.fileExists(atPath: session.notebook.url(for: path).path) {
                session.selection = path
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
            if !fix.notes.isEmpty { Button("Undo") { session.undoLinkFix() } }
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
        let updated = fix.notes.count == 1 ? "Updated links in 1 note" : "Updated links in \(fix.notes.count) notes"
        guard !fix.skipped.isEmpty else { return updated }
        return updated + " · \(fix.skipped.count) changed meanwhile, left as is"
    }
}

struct SidebarView: View {
    @Bindable var session: NotebookSession
    let library: Library
    let addNotebook: () -> Void

    var body: some View {
        List(selection: Binding<NotebookSession.Scope?>(get: { session.scope }, set: { if let s = $0 { session.scope = s } })) {
            Section {
                Label("All Notes", systemImage: "note.text").tag(NotebookSession.Scope.all)
                Label("Pinned", systemImage: "pin").tag(NotebookSession.Scope.pinned)
            }
            Section("Folders") {
                Label(session.name, systemImage: "folder").tag(NotebookSession.Scope.folder(nil))
                OutlineGroup(session.folders, children: \.children) { node in
                    Label(node.name, systemImage: "folder").tag(NotebookSession.Scope.folder(node.path))
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
            if let current = library.entries.first(where: { $0.id == library.selectedID }) {
                Button("Remove “\(current.name)” from nmy") { library.remove(current) }
            }
        } label: {
            Label(session.name, systemImage: "books.vertical").font(.headline)
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
