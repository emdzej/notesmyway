//
//  CommandPalette.swift
//  NmwUI
//
//  ⇧⌘P (on the Mac also in the notebook menu): every command and
//  every note in one fuzzy list. ↑ / ↓ move, Return runs, Esc closes.
//  Commands for the selected note and its editor come first.
//

import MarkdownEngine
import NmwCore
import SwiftUI
#if os(macOS)
import AppKit
#endif

extension Notification.Name {
    /// Toggles formatted / source in the editor whose controller is the object.
    static let nmwToggleSource = Notification.Name("nmw.toggleSource")
}

struct PaletteItem: Identifiable {
    let id: String
    let title: String
    var subtitle: String? = nil
    let systemImage: String
    var shortcut: String? = nil
    /// Extra words it's found by ("delete" finds Move to Trash).
    var keywords = ""
    /// Shows an alert or sheet: run once the palette has closed.
    var presents = false
    /// A second list (e.g. folders for Move to Folder…) instead of an action.
    var next: PaletteStage? = nil
    var run: @MainActor () -> Void = {}
}

enum PaletteStage: Equatable {
    case root
    case moveToFolder(NotebookPath)
}

struct CommandPalette: View {
    let session: NotebookSession
    let library: Library
    @State private var query = ""
    @State private var stage = PaletteStage.root
    @State private var highlighted = 0
    @FocusState private var fieldFocused: Bool
    @AppStorage("nmw.showsInspector") private var showsInspector = false
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: stage == .root ? "command" : "folder").foregroundStyle(.secondary)
                TextField(stage == .root ? "Type a command or a note…" : "Move to folder…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($fieldFocused)
                    .onSubmit(runHighlighted)
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onKeyPress(.escape) { close(); return .handled }
                    #if os(iOS)
                    .submitLabel(.go)
                    #endif
            }
            .padding(12)
            Divider()
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(matches.enumerated()), id: \.element.id) { index, item in
                        Button { run(item) } label: { row(item, isHighlighted: index == highlighted) }
                            .buttonStyle(.plain)
                            .listRowBackground(index == highlighted ? Palette.accentColor.opacity(0.18) : Color.clear)
                            .id(item.id)
                    }
                }
                .listStyle(.plain)
                .onChange(of: highlighted) { _, index in
                    if matches.indices.contains(index) { proxy.scrollTo(matches[index].id) }
                }
            }
            .overlay {
                if matches.isEmpty { ContentUnavailableView.search(text: query) }
            }
        }
        #if os(macOS)
        .frame(width: 560, height: 420)
        #endif
        .onAppear { fieldFocused = true }
        .onChange(of: query) { highlighted = 0 }
        .onChange(of: stage) { query = ""; highlighted = 0 }
    }

    private func row(_ item: PaletteItem, isHighlighted: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.systemImage)
                .frame(width: 22)
                .foregroundStyle(isHighlighted ? Palette.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).lineLimit(1)
                if let subtitle = item.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if let shortcut = item.shortcut {
                Text(shortcut).font(.callout.monospaced()).foregroundStyle(.secondary)
            }
            if item.next != nil { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    // MARK: Matching

    private var matches: [PaletteItem] {
        let items = stage == .root ? rootItems + noteItems : folderItems
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return Array((stage == .root ? rootItems : items).prefix(80)) }
        return items
            .enumerated()
            .compactMap { offset, item -> (PaletteItem, Int, Int)? in
                guard let score = Self.score(q, item) else { return nil }
                return (item, score, offset)
            }
            .sorted { ($0.1, -$0.2) > ($1.1, -$1.2) }
            .prefix(80)
            .map(\.0)
    }

    /// NotePicker's ranking on the title, then the keywords and subtitle.
    static func score(_ query: String, _ item: PaletteItem) -> Int? {
        NotePicker.score(query, item.title.lowercased(),
                         (item.keywords + " " + (item.subtitle ?? "")).lowercased())
    }

    private func move(_ delta: Int) {
        guard !matches.isEmpty else { return }
        highlighted = (highlighted + delta + matches.count) % matches.count
    }

    private func runHighlighted() {
        if matches.indices.contains(highlighted) { run(matches[highlighted]) }
    }

    private func run(_ item: PaletteItem) {
        if let next = item.next { stage = next; return }
        close()
        let action = item.run
        if item.presents {
            // Let the sheet finish closing before an alert or sheet appears.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                action()
            }
        } else {
            action()
        }
    }

    private func close() {
        session.isShowingPalette = false
    }

    // MARK: Items

    private var rootItems: [PaletteItem] {
        var items: [PaletteItem] = []
        if let path = session.selection { items += noteCommands(for: path) }
        if session.activeController != nil, session.selection != nil { items += formatCommands }
        items += generalCommands
        items += places
        items += notebooks
        items += themes
        return items
    }

    private func noteCommands(for path: NotebookPath) -> [PaletteItem] {
        let note = session.notes.first { $0.path == path } ?? (try? session.index.note(at: path))
        let pinned = note?.pinned ?? false
        let controller = session.activeController
        return [
            PaletteItem(id: "source", title: "Toggle Markdown Source", systemImage: "chevron.left.forwardslash.chevron.right",
                        shortcut: "⇧⌘M", keywords: "raw formatted view") {
                NotificationCenter.default.post(name: .nmwToggleSource, object: controller)
            },
            PaletteItem(id: "outline", title: showsInspector ? "Hide Outline and Backlinks" : "Show Outline and Backlinks",
                        systemImage: "sidebar.right", shortcut: "⌥⌘I", keywords: "inspector headings") {
                showsInspector.toggle()
            },
            PaletteItem(id: "pin", title: pinned ? "Unpin Note" : "Pin Note", systemImage: pinned ? "pin.slash" : "pin") {
                Task { try? await session.setPinned(path, !pinned) }
            },
            PaletteItem(id: "rename", title: "Rename Note…", systemImage: "pencil", presents: true) {
                session.renameRequest = path
            },
            PaletteItem(id: "move", title: "Move to Folder…", systemImage: "folder", keywords: "move", next: .moveToFolder(path)),
            PaletteItem(id: "move-notebook", title: "Move to Notebook…", systemImage: "books.vertical", presents: true) {
                session.moveToNotebookRequest = path
            },
            PaletteItem(id: "trash", title: "Move to Trash", systemImage: "trash", keywords: "delete remove") {
                Task { try? await session.moveToTrash(path) }
            },
            PaletteItem(id: "share", title: "Share…", systemImage: "square.and.arrow.up", keywords: "send export airdrop mail", presents: true) {
                Self.export(.share, controller)
            },
            PaletteItem(id: "print", title: "Print…", systemImage: "printer", shortcut: "⌘P", presents: true) {
                Self.export(.print, controller)
            },
        ] + exportPDFCommand(controller)
    }

    private static func export(_ action: NoteExportAction, _ controller: MarkdownEditorController?) {
        NotificationCenter.default.post(name: .nmwExportNote, object: controller, userInfo: ["action": action.rawValue])
    }

    private func exportPDFCommand(_ controller: MarkdownEditorController?) -> [PaletteItem] {
        #if os(macOS)
        [PaletteItem(id: "export-pdf", title: "Export as PDF…", systemImage: "doc.richtext", keywords: "save pdf", presents: true) {
            Self.export(.exportPDF, controller)
        }]
        #else
        []
        #endif
    }

    private var formatCommands: [PaletteItem] {
        guard let controller = session.activeController else { return [] }
        func block(_ id: String, _ title: String, _ image: String, _ shortcut: String?, _ style: MarkdownFormatting.BlockStyle) -> PaletteItem {
            PaletteItem(id: "format-\(id)", title: title, subtitle: "Format", systemImage: image, shortcut: shortcut) {
                controller.setBlockStyle(style)
                controller.focus()
            }
        }
        func inline(_ id: String, _ title: String, _ image: String, _ shortcut: String?, _ style: MarkdownFormatting.InlineStyle) -> PaletteItem {
            PaletteItem(id: "format-\(id)", title: title, subtitle: "Format", systemImage: image, shortcut: shortcut) {
                controller.toggle(style)
                controller.focus()
            }
        }
        return [
            block("title", "Title", "textformat.size.larger", "⇧⌘T", .title),
            block("heading", "Heading", "textformat.size", "⇧⌘H", .heading),
            block("subheading", "Subheading", "textformat.size.smaller", "⇧⌘J", .subheading),
            block("body", "Body", "text.alignleft", "⇧⌘B", .body),
            inline("bold", "Bold", "bold", "⌘B", .bold),
            inline("italic", "Italic", "italic", "⌘I", .italic),
            inline("strike", "Strikethrough", "strikethrough", "⇧⌘X", .strikethrough),
            inline("code", "Code", "chevron.left.forwardslash.chevron.right", "⌘E", .code),
            block("checklist", "Checklist", "checklist", "⇧⌘L", .task),
            block("bullets", "Bulleted List", "list.bullet", "⇧⌘7", .bullet),
            block("numbers", "Numbered List", "list.number", "⇧⌘9", .numbered),
            block("quote", "Quote", "text.quote", "⌘'", .quote),
            PaletteItem(id: "format-table", title: "Insert Table", subtitle: "Format", systemImage: "tablecells", shortcut: "⌥⌘T") {
                controller.insertTable()
                controller.focus()
            },
        ]
    }

    private var currentFolder: NotebookPath? {
        if case .folder(let folder) = session.scope { folder } else { nil }
    }

    private var generalCommands: [PaletteItem] {
        let folder = currentFolder
        var items = [
            PaletteItem(id: "new-note", title: "New Note", systemImage: "square.and.pencil", shortcut: "⌘N", keywords: "create") {
                Task { try? await session.createNote(in: folder) }
            },
            PaletteItem(id: "new-folder", title: "New Folder", systemImage: "folder.badge.plus", keywords: "create") {
                if let made = try? session.createFolder(in: folder) { session.scope = .folder(made) }
            },
            PaletteItem(id: "open-quickly", title: "Open Quickly…", systemImage: "magnifyingglass", shortcut: "⌘O",
                        keywords: "find note switch", presents: true) {
                session.isShowingSwitcher = true
            },
        ]
        #if os(macOS)
        items.append(PaletteItem(id: "settings", title: "Settings…", systemImage: "gearshape", shortcut: "⌘,", keywords: "preferences options") {
            openSettings()
        })
        #else
        items.append(PaletteItem(id: "settings", title: "Settings…", systemImage: "gearshape", keywords: "preferences options", presents: true) {
            session.isShowingSettings = true
        })
        #endif
        return items
    }

    private var places: [PaletteItem] {
        var items = [
            PaletteItem(id: "go-all", title: "Go to All Notes", systemImage: "note.text") { session.scope = .all },
            PaletteItem(id: "go-pinned", title: "Go to Pinned", systemImage: "pin") { session.scope = .pinned },
            PaletteItem(id: "go-trash", title: "Go to Recently Deleted", systemImage: "trash", keywords: "trash restore") {
                session.scope = .trash
            },
            PaletteItem(id: "go-root", title: "Go to \(session.name)", subtitle: "Folder", systemImage: "folder") {
                session.scope = .folder(nil)
            },
        ]
        items += NoteListView.flatten(session.folders).map { folder in
            PaletteItem(id: "go-folder-\(folder.path.rawValue)", title: "Go to \(folder.name)", subtitle: folder.path.rawValue,
                        systemImage: "folder", keywords: "folder") { session.scope = .folder(folder.path) }
        }
        items += session.tags.map { tag in
            PaletteItem(id: "go-tag-\(tag.tag)", title: "Go to #\(tag.tag)", subtitle: "Tag", systemImage: "number") {
                session.scope = .tag(tag.tag)
            }
        }
        return items
    }

    private var notebooks: [PaletteItem] {
        library.entries.filter { $0.id != session.notebook.localID }.map { entry in
            PaletteItem(id: "notebook-\(entry.id)", title: "Switch to \(entry.name)", subtitle: "Notebook", systemImage: "books.vertical") {
                library.selectedID = entry.id
            }
        }
    }

    private var themes: [PaletteItem] {
        let appearance = EditorAppearance.shared
        return appearance.themes.map { theme in
            PaletteItem(id: "theme-\(theme.id)", title: "Theme: \(theme.name)",
                        subtitle: theme.id == appearance.themeID ? "Current theme" : nil,
                        systemImage: theme.id == appearance.themeID ? "paintpalette.fill" : "paintpalette",
                        keywords: "appearance colors") {
                appearance.themeID = theme.id
            }
        }
    }

    private var noteItems: [PaletteItem] {
        ((try? session.index.notes(sortedBy: .modified)) ?? []).map { note in
            PaletteItem(id: "note-\(note.path.rawValue)", title: note.title, subtitle: note.path.rawValue, systemImage: "doc.text") {
                session.scope = .all
                session.selection = note.path
            }
        }
    }

    private var folderItems: [PaletteItem] {
        guard case .moveToFolder(let path) = stage else { return [] }
        var items = [PaletteItem(id: "to-root", title: session.name, subtitle: "Notebook folder", systemImage: "folder") {
            Task { try? await session.move(path, toFolder: nil) }
        }]
        items += NoteListView.flatten(session.folders).map { folder in
            PaletteItem(id: "to-\(folder.path.rawValue)", title: folder.name, subtitle: folder.path.rawValue, systemImage: "folder") {
                Task { try? await session.move(path, toFolder: folder.path) }
            }
        }
        return items
    }
}
