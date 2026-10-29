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
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

public struct LibraryView: View {
    @Bindable var library: Library
    @State private var pickingFolder = false
    @State private var pickingFile = false
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    public init(library: Library) {
        self.library = library
    }

    public var body: some View {
        Group {
            if let session = library.selectedSession {
                NotebookView(session: session, library: library, addNotebook: { pickingFolder = true })
                    .id(session.notebook.localID)
            } else {
                WelcomeView(addNotebook: { pickingFolder = true }, openFile: { pickingFile = true })
            }
        }
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { library.add(folder: url) }
        }
        .fileImporter(isPresented: $pickingFile, allowedContentTypes: [UTType("net.daringfireball.markdown") ?? .plainText, .plainText]) { result in
            if case .success(let url) = result { library.open(file: url) }
        }
        .focusedSceneValue(\.libraryActions, LibraryActions(addNotebook: { pickingFolder = true }, openFile: { pickingFile = true }))
        .onOpenURL { library.open(file: $0) }
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
            Image(systemName: "books.vertical").font(.system(size: 48)).foregroundStyle(.secondary)
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
}

struct NmwCommands: Commands {
    @FocusedValue(\.notebookSession) private var session
    @FocusedValue(\.linkToNote) private var linkToNote
    @FocusedValue(\.libraryActions) private var libraryActions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Note") {
                guard let session else { return }
                let folder: NotebookPath? = if case .folder(let f) = session.scope { f } else { nil }
                Task { try? await session.createNote(in: folder) }
            }
            .keyboardShortcut("n")
            .disabled(session == nil)
            Divider()
            Button("Open File…") { libraryActions?.openFile() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Button("Add Notebook…") { libraryActions?.addNotebook() }
        }
        CommandGroup(after: .newItem) {
            Button("Open Quickly…") { session?.isShowingSwitcher = true }
                .keyboardShortcut("o")
                .disabled(session == nil)
        }
        CommandGroup(after: .textEditing) {
            Button("Link to Note…") { linkToNote?.run() }
                .keyboardShortcut("l")
                .disabled(linkToNote == nil)
        }
    }
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
                .tint(Palette.accentColor)
                #if os(macOS)
                .frame(minWidth: 760, minHeight: 480)
                #endif
        }
        .commands { NmwCommands() }

        #if os(macOS)
        WindowGroup("Note", id: Self.standaloneWindowID, for: URL.self) { $url in
            if let url { StandaloneNoteView(url: url).tint(Palette.accentColor) }
        }

        Settings {
            SettingsView(library: library).tint(Palette.accentColor)
        }
        #endif
    }
}

#if os(macOS)
/// Receives files opened from Finder and saves notes on quit.
@MainActor
public final class NmwAppDelegate: NSObject, NSApplicationDelegate {
    public let library = Library()

    public func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { library.open(file: url) }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        library.shutdown()
    }
}
#endif
