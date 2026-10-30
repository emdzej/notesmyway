//
//  NoteEditorView.swift
//  NmwUI
//
//  The editor for one note (notebook or standalone): the engine view bound
//  to a `NoteEditorModel`, plus the conflict and error bars and the
//  "Link to Note" picker.
//

import MarkdownEngine
import NmwCore
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct NoteEditorView: View {
    @Bindable var model: NoteEditorModel
    let root: URL?
    let previews: LinkPreviewStore?
    var attachments = NotebookConfig.Attachments()
    /// Images or previews changed; restyles the editor.
    let version: Int
    /// Notes the "Link to Note" picker offers; nil hides the picker (standalone files).
    let linkableNotes: (() -> [NoteSummary])?
    let onLink: (LinkAction) -> Void
    let onStoredFiles: @MainActor @Sendable ([URL]) -> Void
    /// Notes linking here, for the inspector; nil for standalone files.
    var backlinks: (() -> [NoteSummary])? = nil
    var onOpenNote: (NotebookPath) -> Void = { _ in }
    /// Shows the note without allowing edits (Recently Deleted).
    var readOnly = false
    /// Where links and images resolve from, when that isn't the file's own
    /// place (a trashed note: where it was).
    var linkBase: URL? = nil
    /// Called with the editor's controller when it appears (the palette's format commands).
    var onController: ((MarkdownEditorController) -> Void)? = nil
    /// An extra bar above the text (e.g. the standalone folder-access prompt).
    var banner: AnyView? = nil

    @State private var controller = MarkdownEditorController()
    @State private var showingLinkPicker = false
    @AppStorage("nmw.showsInspector") private var showsInspector = false
    @AppStorage(EditorMode.key) private var defaultMode = EditorMode.formatted
    /// This note's mode while it's open; nil follows the setting.
    @State private var mode: EditorMode?

    private var effectiveMode: EditorMode { mode ?? defaultMode }
    /// Formatting needs an editable, loaded note.
    private var canFormat: Bool { model.isLoaded && model.errorMessage == nil && !readOnly }

    private var context: NoteContext { NoteContext(noteURL: linkBase ?? model.url, root: root, previews: previews, attachments: attachments) }

    @AppStorage(ChecklistSettings.movesCheckedKey) private var movesCheckedToBottom = false

    private var configuration: MarkdownEditorConfiguration {
        var configuration = EditorSetup.configuration(for: context, version: version, mode: effectiveMode == .source ? .source : .formatted)
        // Round, accent-colored checkboxes, as in Notes.
        configuration.checkbox.shape = .circle
        configuration.checkbox.movesCheckedToBottom = movesCheckedToBottom
        #if os(iOS)
        // Bigger boxes for fingers (the tap target around them is 44 pt).
        configuration.checkbox.sizeFromFontHeightFactor = 1.5
        configuration.checkbox.sizeFromMarkerWidthFactor = 1.7
        #endif
        return configuration
    }

    var body: some View {
        NativeTextViewWrapper(
            text: $model.text,
            configuration: configuration,
            fontName: EditorAppearance.shared.fontName,
            fontSize: EditorAppearance.shared.fontSize,
            documentId: model.documentID,
            isEditable: model.isLoaded && model.errorMessage == nil && !readOnly,
            controller: controller,
            onDropFiles: EditorSetup.dropHandler(for: context, stored: onStoredFiles),
            onLinkClick: { destination in onLink(LinkAction.classify(destination, in: context)) }
        )
        // Bars above the text (conflict, errors, folder access).
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                if let banner { banner }
                if model.conflict != nil { ConflictBar(model: model) }
                if let message = model.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.yellow.opacity(0.15))
                }
            }
            .background(.bar)
        }
        #if os(iOS)
        // Notes-style formatting bar above the keyboard while editing.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if controller.isEditingAnything, model.isLoaded {
                FormatBar(controller: controller,
                          attach: EditorSetup.dropHandler(for: context, stored: onStoredFiles))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.2), value: controller.isEditingAnything)
        #endif
        // The theme's page color fills the whole pane, under the toolbar and bars too.
        .background {
            if let page = EditorAppearance.shared.background(forSource: effectiveMode == .source) {
                page.ignoresSafeArea()
            }
        }
        .inspector(isPresented: $showsInspector) {
            NoteInspector(text: model.text, backlinks: backlinks?(), onHeading: { controller.reveal($0.range) },
                          onOpenNote: onOpenNote)
                .inspectorColumnWidth(min: 200, ideal: 240, max: 360)
        }
        .toolbar {
            #if os(iOS)
            // As in Notes: Share, and the rest in a "…" menu.
            ToolbarItem {
                Button { share() } label: { Label("Share", systemImage: "square.and.arrow.up") }
                    .disabled(!model.isLoaded)
            }
            ToolbarItem {
                Menu {
                    Button("Find in Note", systemImage: "magnifyingglass") { controller.showFind() }
                    Button("Find and Replace", systemImage: "arrow.left.arrow.right") { controller.showFind(replacing: true) }
                    Divider()
                    Button(effectiveMode == .source ? "Show Formatted" : "Show Markdown Source",
                           systemImage: effectiveMode == .source ? "doc.richtext" : "chevron.left.forwardslash.chevron.right") {
                        mode = effectiveMode == .source ? .formatted : .source
                    }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                    Button(showsInspector ? "Hide Outline and Backlinks" : "Outline and Backlinks", systemImage: "sidebar.right") {
                        showsInspector.toggle()
                    }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
            #else
            // Formatting, as in Notes' toolbar: Aa, checklist, table, attachments.
            ToolbarItemGroup {
                MacFormatControls(controller: controller, canEdit: canFormat,
                                  attach: EditorSetup.dropHandler(for: context, stored: onStoredFiles))
            }
            ToolbarItem {
                Button { mode = effectiveMode == .source ? .formatted : .source } label: {
                    Label(effectiveMode == .source ? "Show Formatted" : "Show Markdown Source",
                          systemImage: effectiveMode == .source ? "doc.richtext" : "chevron.left.forwardslash.chevron.right")
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .help(effectiveMode == .source ? "Show Formatted (⇧⌘M)" : "Show Markdown Source (⇧⌘M)")
            }
            ToolbarItem {
                Button { showsInspector.toggle() } label: { Label("Outline and Backlinks", systemImage: "sidebar.right") }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                    .help("Outline and Backlinks (⌥⌘I)")
            }
            ToolbarItem {
                ShareLink(item: NoteShareItem(title: shareTitle, makeExporter: { makeExporter() }),
                          preview: SharePreview(shareTitle)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .disabled(!model.isLoaded)
                .help("Share")
            }
            #endif
        }
        .focusedSceneValue(\.noteExport, NoteExportCommands(noteURL: model.url, run: run))
        .onReceive(NotificationCenter.default.publisher(for: .nmwExportNote)) { note in
            guard note.object as? MarkdownEditorController === controller,
                  let raw = note.userInfo?["action"] as? String, let action = NoteExportAction(rawValue: raw) else { return }
            run(action)
        }
        .task(id: model.url) { if !model.isLoaded { await model.loadInBackground() } }
        .onAppear { onController?(controller) }
        .onReceive(NotificationCenter.default.publisher(for: .nmwToggleSource)) { note in
            if note.object as? MarkdownEditorController === controller {
                mode = effectiveMode == .source ? .formatted : .source
            }
        }
        .onDisappear { model.flush() }
        .focusedSceneValue(\.noteEditor, controller)
        .focusedSceneValue(\.linkToNote, linkableNotes == nil ? nil : LinkToNoteAction(noteURL: model.url) { showingLinkPicker = true })
        .sheet(isPresented: $showingLinkPicker) {
            if let linkableNotes {
                NotePicker(prompt: "Link to note…", notes: linkableNotes()) { note in
                    showingLinkPicker = false
                    insertLink(to: note)
                }
            }
        }
    }

    // MARK: Print, PDF, Share

    private var shareTitle: String {
        NoteMetadata(markdown: model.text, fileName: model.url.deletingPathExtension().lastPathComponent).title
    }

    private func makeExporter() -> NoteExporter {
        NoteExporter(markdown: model.text, title: shareTitle, context: context)
    }

    private func share(anchor: ShareAnchorView? = nil) {
        NoteSharing.share(makeExporter(), anchor: anchor)
    }

    private func run(_ action: NoteExportAction) {
        let exporter = makeExporter()
        switch action {
        case .share: NoteSharing.share(exporter)
        #if os(macOS)
        case .print: Task { await exporter.print(in: NSApp.keyWindow) }
        case .exportPDF: Task { await exporter.exportPDF(in: NSApp.keyWindow) }
        #else
        case .print: Task { await exporter.print() }
        case .exportPDF: NoteSharing.share(exporter)
        #endif
        }
    }

    private func insertLink(to note: NoteSummary) {
        guard let root else { return }
        let target = note.path.url(in: root)
        let destination = LinkPath.encode(LinkPath.relative(from: model.url, to: target))
        let title = note.title.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
        controller.insertText("[\(title)](\(destination))", actionName: "Link to Note")
        controller.focus()
    }
}

/// Outline (click to jump) and the notes linking here.
struct NoteInspector: View {
    let text: String
    /// nil hides the section (standalone files aren't indexed).
    let backlinks: [NoteSummary]?
    let onHeading: (NoteHeading) -> Void
    let onOpenNote: (NotebookPath) -> Void

    var body: some View {
        List {
            Section("Outline") {
                let headings = NoteOutline.headings(in: text)
                if headings.isEmpty {
                    Text("No headings").foregroundStyle(.secondary)
                }
                ForEach(headings) { heading in
                    Button { onHeading(heading) } label: {
                        Text(heading.title)
                            .font(heading.level == 1 ? .body.weight(.semibold) : .body)
                            .padding(.leading, CGFloat(max(0, heading.level - 1)) * 12)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if let backlinks {
                Section("Backlinks") {
                    if backlinks.isEmpty {
                        Text("No notes link here").foregroundStyle(.secondary)
                    }
                    ForEach(backlinks) { note in
                        Button { onOpenNote(note.path) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.title).lineLimit(1)
                                Text(note.path.rawValue).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// Shown when the file changed on disk while the editor had unsaved edits.
struct ConflictBar: View {
    let model: NoteEditorModel

    var body: some View {
        HStack(spacing: 12) {
            Label("This note changed on disk while you were editing it.", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                .font(.callout)
            Spacer()
            Button("Keep Mine") { model.resolveConflict(.keepMine) }
            Button("Use Disk Version") { model.resolveConflict(.useDisk) }
            Button("Keep Both") { model.resolveConflict(.keepBoth) }
                .help("Saves your text and keeps the other version as a “(conflict …)” copy.")
        }
        .controlSize(.small)
        .padding(10)
        .background(.orange.opacity(0.15))
    }
}

/// Fuzzy picker over the notebook's notes: "Link to Note" (⌘L) and the quick switcher (⌘O).
struct NotePicker: View {
    let prompt: String
    let notes: [NoteSummary]
    let onPick: (NoteSummary) -> Void
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var matches: [NoteSummary] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return Array(notes.prefix(50)) }
        return notes
            .compactMap { note in Self.score(q, note.title.lowercased(), note.path.rawValue.lowercased()).map { (note, $0) } }
            .sorted { $0.1 > $1.1 }
            .prefix(50)
            .map(\.0)
    }

    /// Subsequence match; consecutive and word-start hits score higher. Title beats path.
    static func score(_ query: String, _ title: String, _ path: String) -> Int? {
        func subsequence(_ text: String) -> Int? {
            var score = 0
            var index = text.startIndex
            var previousMatched = false
            for c in query {
                guard let found = text[index...].firstIndex(of: c) else { return nil }
                let atWordStart = found == text.startIndex || !text[text.index(before: found)].isLetter
                score += 1 + (previousMatched && found == index ? 3 : 0) + (atWordStart ? 2 : 0)
                previousMatched = true
                index = text.index(after: found)
            }
            return score
        }
        if let s = subsequence(title) { return s * 2 + (title.hasPrefix(query) ? 10 : 0) }
        return subsequence(path)
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(prompt, text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(12)
                .onSubmit { if let first = matches.first { onPick(first) } }
            Divider()
            List(matches) { note in
                Button { onPick(note) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.title).lineLimit(1)
                        Text(note.path.rawValue).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #endif
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }
}
