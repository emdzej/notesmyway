//
//  SettingsView.swift
//  NmwUI
//
//  Per-notebook settings (stored in the notebook's `.nmw/config.json`):
//  where attachments go, whether their folders show in the sidebar, and
//  web previews. macOS shows them in the Settings window (⌘,), iOS in a
//  sheet from the notebook menu.
//

import NmwCore
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// The Settings window: app-wide look, and the selected notebook's settings.
public struct SettingsView: View {
    @Bindable var library: Library

    public init(library: Library) {
        self.library = library
    }

    public var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsForm()
            }
            Tab("Notebook", systemImage: "books.vertical") {
                notebook
            }
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var notebook: some View {
        if let session = library.selectedSession {
            VStack(alignment: .leading, spacing: 0) {
                if library.entries.count > 1 {
                    Picker("Notebook", selection: Binding(get: { library.selectedID ?? "" }, set: { library.selectedID = $0 })) {
                        ForEach(library.entries) { Text($0.name).tag($0.id) }
                    }
                    .padding([.horizontal, .top], 20)
                }
                Text("Settings for “\(session.name)”, saved in the notebook (.nmw/config.json) so they sync with it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding([.horizontal, .top], 20)
                NotebookSettingsForm(session: session).id(session.notebook.localID)
            }
        } else {
            ContentUnavailableView("No Notebook", systemImage: "books.vertical",
                                   description: Text("Open a folder as a notebook to change its settings."))
                .padding(40)
        }
    }
}

/// Settings for the app on this device (not synced with notebooks).
struct GeneralSettingsForm: View {
    @AppStorage(AppAppearance.key) private var appearance = AppAppearance.system
    @AppStorage(SidebarStyle.key) private var sidebarStyle = SidebarStyle.system
    @AppStorage(EditorMode.key) private var editorMode = EditorMode.formatted

    var body: some View {
        Form {
            Section("Look") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                }
                Picker("Sidebar", selection: $sidebarStyle) {
                    ForEach(SidebarStyle.allCases) { Text($0.title).tag($0) }
                }
            }
            Section {
                Picker("Notes open as", selection: $editorMode) {
                    ForEach(EditorMode.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Editor")
            } footer: {
                Text("Switch the open note with the </> toolbar button (⇧⌘M).").foregroundStyle(.secondary)
            }
            EditorThemeSection()
            #if os(macOS)
            MarkdownDefaultAppSection()
            #endif
        }
        .formStyle(.grouped)
    }
}

#if os(macOS)
/// Which app opens .md files from Finder, and a button to make it this one.
struct MarkdownDefaultAppSection: View {
    @State private var current: URL?
    @State private var errorMessage: String?

    private static let markdown = UTType("net.daringfireball.markdown") ?? .plainText

    private var isDefault: Bool {
        current?.resolvingSymlinksInPath().path == Bundle.main.bundleURL.resolvingSymlinksInPath().path
    }

    var body: some View {
        Section {
            LabeledContent("Opens Markdown files") {
                Text(current.map { FileManager.default.displayName(atPath: $0.path) } ?? "None")
            }
            if !isDefault {
                Button("Make Notes my Way the Default") { makeDefault() }
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        } header: {
            Text("Markdown Files")
        } footer: {
            Text("Files opened from Finder that aren’t in a notebook open in their own window.").foregroundStyle(.secondary)
        }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        current = NSWorkspace.shared.urlForApplication(toOpen: Self.markdown)
    }

    private func makeDefault() {
        // macOS asks the user to confirm the change.
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: Self.markdown) { error in
            Task { @MainActor in
                errorMessage = error?.localizedDescription
                refresh()
            }
        }
    }
}
#endif

struct NotebookSettingsForm: View {
    let session: NotebookSession
    @State private var folderName = ""
    @State private var errorMessage: String?

    private var attachments: NotebookConfig.Attachments { session.config.attachments }

    var body: some View {
        Form {
            Section {
                TextField("Folder name", text: $folderName)
                    .onSubmit(commitFolderName)
                Picker("Location", selection: binding(\.attachments.placement)) {
                    Text("Next to the note").tag(NotebookConfig.AttachmentPlacement.nextToNote)
                    Text("In the notebook folder").tag(NotebookConfig.AttachmentPlacement.notebookRoot)
                }
                Toggle("Show attachment folders in the sidebar", isOn: binding(\.attachments.showInSidebar))
            } header: {
                Text("Attachments")
            } footer: {
                Text(example + "\nChanging these doesn’t move files that are already there.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Rename files to match the first heading", isOn: binding(\.renameFilesToTitle))
            } header: {
                Text("File Names")
            } footer: {
                Text("When a note’s first heading changes, its file is renamed after it once you pause typing or leave the note. Links to it are updated. Notes without a heading, or named “Untitled…”, keep their name.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Load previews for web links", isOn: binding(\.webPreviews))
            } header: {
                Text("Link Previews")
            } footer: {
                Text("Only links marked {.preview} are fetched.").foregroundStyle(.secondary)
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .onAppear { folderName = attachments.folderName }
        .onDisappear(perform: commitFolderName)
    }

    /// Where a file dropped into `Projects/Idea.md` would go.
    private var example: String {
        let name = folderName.isEmpty ? attachments.folderName : folderName
        switch attachments.placement {
        case .nextToNote: return "Files dropped into Projects/Idea.md go to Projects/\(name)/."
        case .notebookRoot: return "Files dropped into Projects/Idea.md go to \(name)/Idea/."
        }
    }

    private func commitFolderName() {
        let name = folderName.trimmingCharacters(in: .whitespaces)
        guard name != attachments.folderName else { return }
        guard NotebookConfig.Attachments.isValidFolderName(name) else {
            errorMessage = "“\(name)” can’t be used as a folder name."
            folderName = attachments.folderName
            return
        }
        var config = session.config
        config.attachments.folderName = name
        save(config)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<NotebookConfig, Value>) -> Binding<Value> {
        Binding(get: { session.config[keyPath: keyPath] }, set: { value in
            var config = session.config
            config[keyPath: keyPath] = value
            save(config)
        })
    }

    private func save(_ config: NotebookConfig) {
        do {
            try session.updateConfig(config)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
