//
//  TrashView.swift
//  NmwUI
//
//  Recently Deleted: the notebook's `.nmw/trash`. The list shows where each
//  item was and how long it's kept; a note opens read-only; items can be
//  restored, deleted for good, or all emptied.
//

import NmwCore
import SwiftUI

struct TrashListView: View {
    @Bindable var session: NotebookSession
    @State private var deleting: TrashItem?
    @State private var emptying = false
    @State private var errorMessage: String?

    var body: some View {
        List(selection: $session.trashSelection) {
            ForEach(session.trashItems) { item in
                TrashRow(item: item)
                    .tag(item.id)
                    .contextMenu {
                        Button("Restore") { restore(item) }
                        Divider()
                        Button("Delete Now…", role: .destructive) { deleting = item }
                    }
                    #if os(iOS)
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash", role: .destructive) { deleting = item }
                            .tint(.red)
                    }
                    .swipeActions(edge: .leading) {
                        Button("Restore", systemImage: "arrow.uturn.backward") { restore(item) }
                            .tint(Palette.accentColor)
                    }
                    #endif
            }
        }
        #if os(macOS)
        .onDeleteCommand {
            if let id = session.trashSelection, let item = session.trashItems.first(where: { $0.id == id }) { deleting = item }
        }
        #endif
        .overlay {
            if session.trashItems.isEmpty {
                ContentUnavailableView("No Recently Deleted Notes", systemImage: "trash",
                                       description: Text("Deleted notes and folders stay here for \(NotebookTrash.keepDays) days."))
            }
        }
        .navigationTitle("Recently Deleted")
        .toolbar {
            ToolbarItem {
                Button("Empty Trash", role: .destructive) { emptying = true }
                    .disabled(session.trashItems.isEmpty)
            }
        }
        .onAppear { session.refreshTrash() }
        .confirmationDialog("Delete “\(deleting?.name ?? "")” Now?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete Now", role: .destructive) {
                if let item = deleting { attempt { try session.deleteForever(item) } }
            }
        } message: { Text("This can’t be undone.") }
        .confirmationDialog("Empty the Trash?", isPresented: $emptying, titleVisibility: .visible) {
            Button("Delete \(session.trashItems.count == 1 ? "1 Item" : "\(session.trashItems.count) Items")", role: .destructive) {
                attempt { try session.emptyTrash() }
            }
        } message: { Text("Everything in Recently Deleted is deleted. This can’t be undone.") }
        .alert("Couldn’t Complete", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func restore(_ item: TrashItem) {
        Task { @MainActor in
            do { try await session.restore(item) } catch { errorMessage = error.localizedDescription }
        }
    }

    private func attempt(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }
}

struct TrashRow: View {
    let item: TrashItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.isFolder ? "folder" : "doc.text")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.isNote ? item.originalPath.stem : item.name).font(.headline).lineLimit(1)
                Text("Was in \(item.originalPath.parent?.rawValue ?? "the notebook’s folder")")
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Text("Deleted \(item.deletedAt.formatted(.dateTime.day().month(.abbreviated))) · \(daysLeft)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var daysLeft: String {
        switch item.daysLeft() {
        case 0: "deleted for good today"
        case 1: "1 day left"
        case let n: "\(n) days left"
        }
    }
}

/// The selected trash item: a note read-only, or what a folder holds.
struct TrashDetail: View {
    let session: NotebookSession
    @State private var model: NoteEditorModel?
    @State private var errorMessage: String?

    private var item: TrashItem? {
        session.trashSelection.flatMap { id in session.trashItems.first { $0.id == id } }
    }

    var body: some View {
        Group {
            if let item, item.isNote, let model, model.url == item.url {
                NoteEditorView(
                    model: model,
                    root: session.notebook.root,
                    previews: session.previews,
                    attachments: session.config.attachments,
                    version: session.contentVersion,
                    linkableNotes: nil,
                    onLink: { _ in },
                    onStoredFiles: { _ in },
                    readOnly: true,
                    linkBase: session.notebook.url(for: item.originalPath),
                    banner: AnyView(RestoreBar(item: item, restore: { restore(item) }))
                )
                .id(item.id)
            } else if let item {
                ContentUnavailableView {
                    Label(item.name, systemImage: item.isFolder ? "folder" : "doc")
                } description: {
                    Text(item.isFolder ? "\(noteCount(in: item)) notes. Restore the folder to open them." : "Restore the file to open it.")
                } actions: {
                    Button("Restore") { restore(item) }.buttonStyle(.borderedProminent)
                }
            } else {
                ContentUnavailableView("Nothing Selected", systemImage: "trash",
                                       description: Text("Select a deleted note to see it, or restore it."))
                    .background { WelcomeBackground() }
            }
        }
        .task(id: session.trashSelection) {
            guard let item, item.isNote else { model = nil; return }
            let model = NoteEditorModel(url: item.url)
            model.load()
            self.model = model
        }
        .alert("Couldn’t Restore", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func noteCount(in item: TrashItem) -> Int {
        let files = FileManager.default.enumerator(at: item.url, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []
        return files.filter { FileKind.noteExtensions.contains($0.pathExtension.lowercased()) }.count
    }

    private func restore(_ item: TrashItem) {
        Task { @MainActor in
            do { try await session.restore(item) } catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct RestoreBar: View {
    let item: TrashItem
    let restore: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label("In Recently Deleted · \(item.daysLeft()) days left", systemImage: "trash")
                .font(.callout)
            Spacer()
            Button("Restore", action: restore)
        }
        .controlSize(.small)
        .padding(10)
        .background(Palette.accentColor.opacity(0.12))
    }
}
