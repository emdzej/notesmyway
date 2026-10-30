//
//  LibraryView.swift
//  NmwUI
//
//  Root of the main window: the selected notebook, or a welcome screen.
//  Also routes `.md` files opened from Finder / Files, and hosts the
//  scenes, menu commands and standalone-file windows.
//

import MarkdownEngine
import NmwCore
import SwiftUI
import CoreSpotlight
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

public struct LibraryView: View {
    @Bindable var library: Library
    /// What the file picker is open for. One picker for both: SwiftUI shows
    /// only one `.fileImporter` per view, so with two the folder picker never
    /// appeared and "Open a Folder as Notebook…" did nothing.
    @State private var picking: Picking?
    @Environment(\.scenePhase) private var scenePhase

    private enum Picking {
        case folder, file

        var types: [UTType] {
            switch self {
            case .folder: [.folder]
            case .file: [UTType("net.daringfireball.markdown") ?? .plainText, .plainText]
            }
        }
    }
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    public init(library: Library) {
        self.library = library
    }

    public var body: some View {
        Group {
            if let session = library.selectedSession {
                NotebookView(session: session, library: library, addNotebook: { picking = .folder })
                    .id(session.notebook.localID)
            } else {
                WelcomeView(addNotebook: { picking = .folder }, openFile: { picking = .file })
            }
        }
        .fileImporter(isPresented: Binding(get: { picking != nil }, set: { if !$0 { picking = nil } }),
                      allowedContentTypes: picking?.types ?? [.item]) { [picking] result in
            guard case .success(let url) = result else { return }
            switch picking {
            case .folder: library.add(folder: url)
            case .file: library.open(file: url)
            case nil: break
            }
        }
        .focusedSceneValue(\.libraryActions, LibraryActions(addNotebook: { picking = .folder }, openFile: { picking = .file }))
        // `notesmyway://` links (widgets, Shortcuts), a theme file, else a Markdown file.
        .onOpenURL { url in
            if ThemeInstaller.isTheme(url) { ThemeInstaller.shared.open(url) }
            else if !library.handle(url) { library.open(file: url) }
        }
        .themeInstallAlerts()
        .onContinueUserActivity(CSSearchableItemActionType) { library.handle(spotlightActivity: $0) }
        .onChange(of: scenePhase, initial: true) { _, phase in if phase == .active { library.activateIntegration() } }
        #if os(macOS)
        .onChange(of: library.pendingStandaloneFiles, initial: true) { _, files in
            guard !files.isEmpty else { return }
            library.pendingStandaloneFiles = []
            for url in files { openWindow(id: NmwScenes.standaloneWindowID, value: url) }
        }
        #else
        .sheet(item: Binding(get: { library.pendingStandaloneFiles.first.map(StandaloneFile.init) },
                             set: { if $0 == nil, !library.pendingStandaloneFiles.isEmpty { library.pendingStandaloneFiles.removeFirst() } })) { file in
            NavigationStack { StandaloneNoteView(url: file.url) }
        }
        #endif
    }
}

private struct StandaloneFile: Identifiable {
    let url: URL
    var id: URL { url }
}

struct WelcomeView: View {
    let addNotebook: () -> Void
    let openFile: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            AppIconImage().frame(width: 96, height: 96)
            Text("Welcome to Notes my Way").font(.title2.bold())
            Text("A notebook is any folder of Markdown files. Your notes stay plain .md files you can open anywhere.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            Button("Open a Folder as Notebook…", action: addNotebook)
                .buttonStyle(.borderedProminent)
                .padding(.top, 6)
            Button("Open a Markdown File…", action: openFile)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { WelcomeBackground() }
    }
}

/// The app icon on macOS; on iOS (no public API for it) the icon's motif.
struct AppIconImage: View {
    var body: some View {
        #if os(macOS)
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .interpolation(.high)
        #else
        // iOS apps can't read their own icon; the app's catalog has a copy ("WelcomeIcon").
        Image("WelcomeIcon", bundle: .main)
            .resizable()
            .interpolation(.high)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        #endif
    }
}

/// A soft accent glow and, as a watermark, the icon's page with a `#`, very faint.
struct WelcomeBackground: View {
    /// The mark's color; nil uses the accent. ("My Way" sidebar: white.)
    var tint: Color? = nil
    var glow = true
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height) * 0.95
            ZStack {
                if glow {
                    RadialGradient(colors: [Palette.accentColor.opacity(colorScheme == .dark ? 0.16 : 0.10), .clear],
                                   center: .top, startRadius: 0, endRadius: max(proxy.size.width, proxy.size.height) * 0.8)
                }
                // Bottom right, partly off the edge, clear of the centred content.
                NotePageMark(lineWidth: side * 0.016)
                    .stroke((tint ?? Palette.accentColor).opacity(colorScheme == .dark ? 0.11 : 0.08),
                            style: StrokeStyle(lineWidth: side * 0.016, lineCap: .round, lineJoin: .round))
                    .frame(width: side * 0.62, height: side * 0.78)
                    .rotationEffect(.degrees(-10))
                    .position(x: proxy.size.width - side * 0.18, y: proxy.size.height - side * 0.2)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A page with a folded top-right corner and a `#` on it, as one shape.
struct NotePageMark: Shape {
    var lineWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(rect.width, rect.height) * 0.08
        let fold = min(rect.width, rect.height) * 0.26
        let minX = rect.minX, minY = rect.minY, maxX = rect.maxX, maxY = rect.maxY
        // Outline with the folded corner.
        path.move(to: CGPoint(x: minX + r, y: minY))
        path.addLine(to: CGPoint(x: maxX - fold, y: minY))
        path.addLine(to: CGPoint(x: maxX, y: minY + fold))
        path.addLine(to: CGPoint(x: maxX, y: maxY - r))
        path.addQuadCurve(to: CGPoint(x: maxX - r, y: maxY), control: CGPoint(x: maxX, y: maxY))
        path.addLine(to: CGPoint(x: minX + r, y: maxY))
        path.addQuadCurve(to: CGPoint(x: minX, y: maxY - r), control: CGPoint(x: minX, y: maxY))
        path.addLine(to: CGPoint(x: minX, y: minY + r))
        path.addQuadCurve(to: CGPoint(x: minX + r, y: minY), control: CGPoint(x: minX, y: minY))
        path.closeSubpath()
        // The fold.
        path.move(to: CGPoint(x: maxX - fold, y: minY))
        path.addLine(to: CGPoint(x: maxX - fold, y: minY + fold))
        path.addLine(to: CGPoint(x: maxX, y: minY + fold))
        // The `#`: two slanted verticals, two horizontals.
        let cx = rect.midX, cy = rect.midY + rect.height * 0.04
        let w = rect.width * 0.46, h = rect.height * 0.38, slant = w * 0.12
        for dx in [-w * 0.2, w * 0.2] {
            path.move(to: CGPoint(x: cx + dx + slant, y: cy - h / 2))
            path.addLine(to: CGPoint(x: cx + dx - slant, y: cy + h / 2))
        }
        for dy in [-h * 0.18, h * 0.18] {
            path.move(to: CGPoint(x: cx - w / 2, y: cy + dy))
            path.addLine(to: CGPoint(x: cx + w / 2, y: cy + dy))
        }
        return path
    }
}

/// A `.md` file outside every notebook, in its own window (spec §3.4).
public struct StandaloneNoteView: View {
    let url: URL
    @State private var model: NoteEditorModel
    @State private var previews = StandalonePreviews()
    @State private var needsFolderAccess = false
    #if !os(macOS)
    @State private var pickingFolder = false
    #endif
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    private var folder: URL { url.deletingLastPathComponent() }

    public init(url: URL) {
        self.url = url
        _model = State(initialValue: NoteEditorModel(url: url))
    }

    public var body: some View {
        NoteEditorView(model: model, root: nil, previews: previews.store, version: previews.version,
                       linkableNotes: nil, onLink: handle, onStoredFiles: { _ in previews.version += 1 },
                       banner: needsFolderAccess ? AnyView(folderAccessBar) : nil)
            .navigationTitle(model.fileName)
            #if os(iOS)
            .toolbarTitleDisplayMode(.inline)
            #endif
            .onAppear { needsFolderAccess = !FolderGrants.restore(covering: folder) }
            #if !os(macOS)
            .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
                if case .success(let granted) = result { FolderGrants.remember(granted); refreshAccess() }
            }
            #endif
            #if os(macOS)
            .navigationSubtitle(url.deletingLastPathComponent().path)
            #endif
            .onChange(of: scenePhase) { _, phase in if phase == .active { model.diskDidChange() } }
            #if os(macOS)
            .frame(minWidth: 480, minHeight: 360)
            #endif
    }

    private func handle(_ action: LinkAction) {
        switch action {
        case .standalone(let url), .file(let url), .external(let url): openURL(url)
        case .note, .none: break
        }
    }

    private var folderAccessBar: some View {
        HStack(spacing: 12) {
            Label("Allow access to “\(folder.lastPathComponent)” to show this note’s images and save dropped files next to it.",
                  systemImage: "folder.badge.questionmark")
                .font(.callout)
            Spacer()
            Button("Allow…") {
                #if os(macOS)
                if FolderGrants.request(folder) { refreshAccess() }
                #else
                pickingFolder = true
                #endif
            }
            Button { needsFolderAccess = false } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
        }
        .controlSize(.small)
        .padding(10)
        .background(.blue.opacity(0.08))
    }

    private func refreshAccess() {
        needsFolderAccess = !FolderGrants.isAccessible(folder)
        previews.version += 1   // images can load now
    }
}

/// A preview store for standalone files (memory only), with an observable version.
@MainActor
@Observable
final class StandalonePreviews {
    var version = 0
    let store: LinkPreviewStore

    init() {
        let bump = Bump()
        let cache = (Library.defaultStorage ?? FileManager.default.temporaryDirectory).appending(path: "previews/standalone")
        store = LinkPreviewStore(cacheFolder: cache, index: nil, onChange: { bump.fire() })
        bump.action = { [weak self] in self?.version += 1 }
    }
}

// MARK: - Focused values and commands

/// Focused actions; equal by identity so SwiftUI doesn't re-render on every update.
struct LibraryActions: Equatable {
    let addNotebook: () -> Void
    let openFile: () -> Void
    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

struct LinkToNoteAction: Equatable {
    let noteURL: URL
    let run: () -> Void
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.noteURL == rhs.noteURL }
}

extension FocusedValues {
    @Entry var notebookSession: NotebookSession?
    @Entry var linkToNote: LinkToNoteAction?
    @Entry var libraryActions: LibraryActions?
    @Entry var noteEditor: MarkdownEditorController?
    @Entry var noteExport: NoteExportCommands?
}

struct NmwCommands: Commands {
    @FocusedValue(\.notebookSession) private var session
    @FocusedValue(\.linkToNote) private var linkToNote
    @FocusedValue(\.libraryActions) private var libraryActions
    @FocusedValue(\.noteEditor) private var editor
    @FocusedValue(\.noteExport) private var export

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Note", systemImage: "square.and.pencil") {
                guard let session else { return }
                let folder: NotebookPath? = if case .folder(let f) = session.scope { f } else { nil }
                Task { try? await session.createNote(in: folder) }
            }
            .keyboardShortcut("n")
            .disabled(session == nil)
            Divider()
            Button("Open File…", systemImage: "doc") { libraryActions?.openFile() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Button("Add Notebook…", systemImage: "plus") { libraryActions?.addNotebook() }
            #if os(macOS)
            Divider()
            Button("Import from Apple Notes…", systemImage: "square.and.arrow.down.on.square") {
                session?.isShowingAppleNotesImport = true
            }
            .disabled(session == nil)
            #endif
        }
        CommandGroup(replacing: .printItem) {
            Button("Print…", systemImage: "printer") { export?.run(.print) }
                .keyboardShortcut("p")
                .disabled(export == nil)
            #if os(macOS)
            Button("Export as PDF…", systemImage: "doc.richtext") { export?.run(.exportPDF) }
                .disabled(export == nil)
            #endif
            Button("Share…", systemImage: "square.and.arrow.up") { export?.run(.share) }
                .disabled(export == nil)
        }
        CommandGroup(after: .newItem) {
            Button("Open Quickly…", systemImage: "magnifyingglass") { session?.isShowingSwitcher = true }
                .keyboardShortcut("o")
                .disabled(session == nil)
            Button("Command Palette…", systemImage: "command") { session?.isShowingPalette = true }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(session == nil)
        }
        CommandGroup(after: .textEditing) {
            Button("Link to Note…", systemImage: "link") { linkToNote?.run() }
                .keyboardShortcut("l")
                .disabled(linkToNote == nil)
        }
        CommandMenu("Format") {
            Group {
            // Paragraph and character styles (Apple Notes' shortcuts).
            Button("Title", systemImage: "textformat.size.larger") { editor?.setBlockStyle(.title) }.keyboardShortcut("t", modifiers: [.command, .shift])
            Button("Heading", systemImage: "textformat.size") { editor?.setBlockStyle(.heading) }.keyboardShortcut("h", modifiers: [.command, .shift])
            Button("Subheading", systemImage: "textformat.size.smaller") { editor?.setBlockStyle(.subheading) }.keyboardShortcut("j", modifiers: [.command, .shift])
            Button("Body", systemImage: "text.alignleft") { editor?.setBlockStyle(.body) }.keyboardShortcut("b", modifiers: [.command, .shift])
            Divider()
            Button("Bold", systemImage: "bold") { editor?.toggle(.bold) }.keyboardShortcut("b")
            Button("Italic", systemImage: "italic") { editor?.toggle(.italic) }.keyboardShortcut("i")
            Button("Strikethrough", systemImage: "strikethrough") { editor?.toggle(.strikethrough) }.keyboardShortcut("x", modifiers: [.command, .shift])
            Button("Code", systemImage: "chevron.left.forwardslash.chevron.right") { editor?.toggle(.code) }.keyboardShortcut("e")
            Divider()
            Button("Checklist", systemImage: "checklist") { editor?.setBlockStyle(.task) }.keyboardShortcut("l", modifiers: [.command, .shift])
            Menu("Checklist Items", systemImage: "checklist") {
                Button("Mark as Checked", systemImage: "checkmark.circle") { editor?.checklist(.toggleChecked) }.keyboardShortcut("u", modifiers: [.command, .shift])
                Button("Check All", systemImage: "checklist.checked") { editor?.checklist(.checkAll) }
                Button("Uncheck All", systemImage: "checklist.unchecked") { editor?.checklist(.uncheckAll) }
                Divider()
                Button("Move Checked to Bottom", systemImage: "arrow.down.to.line") { editor?.checklist(.moveCheckedToBottom) }
                Button("Delete Checked", systemImage: "trash") { editor?.checklist(.deleteChecked) }
            }
            Button("Bulleted List", systemImage: "list.bullet") { editor?.setBlockStyle(.bullet) }.keyboardShortcut("7", modifiers: [.command, .shift])
            Button("Numbered List", systemImage: "list.number") { editor?.setBlockStyle(.numbered) }.keyboardShortcut("9", modifiers: [.command, .shift])
            Button("Quote", systemImage: "text.quote") { editor?.setBlockStyle(.quote) }.keyboardShortcut("'")
            Button("Indent", systemImage: "increase.indent") { editor?.indent() }.keyboardShortcut("]")
            Button("Outdent", systemImage: "decrease.indent") { editor?.outdent() }.keyboardShortcut("[")
            Divider()
            Button("Table", systemImage: "tablecells") { editor?.insertTable() }.keyboardShortcut("t", modifiers: [.command, .option])
            Divider()
            // Act on the image or link at the caret; no-ops elsewhere.
            Menu("Image Size", systemImage: "photo.badge.plus") {
                Button("Original", systemImage: "photo") { _ = editor?.setImageSize(nil) }
                Divider()
                ForEach(Self.sizes, id: \.1) { size, title in
                    Button(title, systemImage: Self.sizeIcon(size)) { _ = editor?.setImageSize(size) }
                }
            }
            Menu("Align", systemImage: "text.aligncenter") {
                Button("Left", systemImage: "text.alignleft") { _ = editor?.setAlignment(.left) }
                Button("Center", systemImage: "text.aligncenter") { _ = editor?.setAlignment(.center) }
                Button("Right", systemImage: "text.alignright") { _ = editor?.setAlignment(.right) }
            }
            Divider()
            Button("Show Link as Preview Card", systemImage: "text.below.photo") { _ = editor?.setLinkPreview(true) }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            Button("Show Card as Link", systemImage: "link") { _ = editor?.setLinkPreview(false) }
            }
            .disabled(editor == nil)
        }
    }

    private static func sizeIcon(_ size: MarkdownAttributes.Size) -> String {
        switch size {
        case .icon: "app"
        case .small: "s.square"
        case .medium: "m.square"
        case .large: "l.square"
        case .full: "arrow.left.and.right.square"
        }
    }

    private static let sizes: [(MarkdownAttributes.Size, String)] = [
        (.icon, "Icon"), (.small, "Small"), (.medium, "Medium"), (.large, "Large"), (.full, "Full Width"),
    ]
}

/// The app's scenes; the app target's `@main` just returns these.
public struct NmwScenes: Scene {
    static let standaloneWindowID = "standalone-note"
    let library: Library

    public init(library: Library) {
        self.library = library
    }

    public var body: some Scene {
        WindowGroup("Notes my Way", id: "main") {
            LibraryView(library: library)
                .appLook()
                #if os(macOS)
                .frame(minWidth: 760, minHeight: 480)
                #endif
        }
        .commands { NmwCommands() }

        #if os(macOS)
        WindowGroup("Note", id: Self.standaloneWindowID, for: URL.self) { $url in
            if let url { StandaloneNoteView(url: url).appLook() }
        }

        Settings {
            SettingsView(library: library).appLook()
        }
        #endif
    }
}

#if os(macOS)
/// Receives files opened from Finder and saves notes on quit.
@MainActor
public final class NmwAppDelegate: NSObject, NSApplicationDelegate {
    public let library = Library.shared

    public func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where !library.handle(url) { library.open(file: url) }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        library.shutdown()
    }
}
#endif
