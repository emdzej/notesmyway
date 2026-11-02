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
            Tab("Appearance", systemImage: "paintpalette") {
                AppearanceSettingsForm()
            }
            Tab("Themes", systemImage: "swatchpalette") {
                ThemesSettingsForm()
            }
            Tab("Notebook", systemImage: "books.vertical") {
                notebook
            }
            Tab("About", systemImage: "info.circle") {
                AboutView()
            }
        }
        .themeInstallAlerts(inSettings: true)
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

/// Settings for the app on this device (not synced with notebooks): the editor, and Markdown files.
struct GeneralSettingsForm: View {
    @AppStorage(EditorMode.key) private var editorMode = EditorMode.formatted
    @AppStorage(ChecklistSettings.movesCheckedKey) private var movesCheckedToBottom = false
    @State private var language = AppLanguage.current()

    var body: some View {
        Form {
            LanguageSection(language: $language)
            Section {
                Picker("Notes open as", selection: $editorMode) {
                    ForEach(EditorMode.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Move checked items to the bottom", isOn: $movesCheckedToBottom)
            } header: {
                Text("Editor")
            } footer: {
                Text("Switch the open note with the </> toolbar button (⇧⌘M).").foregroundStyle(.secondary)
            }
            #if os(macOS)
            MarkdownDefaultAppSection()
            #endif
        }
        .formStyle(.grouped)
    }
}

/// System, English or Polski; applies when the app next starts.
private struct LanguageSection: View {
    @Binding var language: AppLanguage

    /// The chosen language differs from the one showing.
    private var needsRestart: Bool {
        let wanted = language == .system
            ? (Locale.preferredLanguages.first?.hasPrefix("pl") == true ? AppLanguage.polish : .english)
            : language
        return wanted != AppLanguage.running
    }

    var body: some View {
        Section {
            Picker("Language", selection: $language) {
                ForEach(AppLanguage.allCases) { Text(verbatim: $0.title).tag($0) }
            }
            .onChange(of: language) { _, new in new.apply() }
            #if os(macOS)
            if needsRestart {
                Button("Restart Notes my Way") { Self.relaunch() }
            }
            #endif
        } footer: {
            if needsRestart {
                #if os(macOS)
                Text("The new language shows after Notes my Way restarts.").foregroundStyle(.secondary)
                #else
                Text("The new language shows after you close Notes my Way and open it again.").foregroundStyle(.secondary)
                #endif
            }
        }
    }

    #if os(macOS)
    /// Opens a new copy of the app, then quits this one (which saves open notes).
    private static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
    #endif
}

/// The theme, light / dark, the sidebar, and the editor's text.
struct AppearanceSettingsForm: View {
    @AppStorage(SidebarStyle.key) private var sidebarStyle = SidebarStyle.system

    var body: some View {
        Form {
            Section {
                ThemePicker()
                AppearancePicker()
                Picker("Sidebar", selection: $sidebarStyle) {
                    ForEach(SidebarStyle.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Look")
            } footer: {
                Text("The theme colors the notes, the note list and the app’s accent.").foregroundStyle(.secondary)
            }
            EditorTextSection()
        }
        .formStyle(.grouped)
    }
}

/// Installed themes: install, duplicate, share, delete.
struct ThemesSettingsForm: View {
    var body: some View {
        Form { ThemeLibrarySection() }
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
        case .nextToNote: return String(localized: "Files dropped into Projects/Idea.md go to Projects/\(name)/.")
        case .notebookRoot: return String(localized: "Files dropped into Projects/Idea.md go to \(name)/Idea/.")
        }
    }

    private func commitFolderName() {
        let name = folderName.trimmingCharacters(in: .whitespaces)
        guard name != attachments.folderName else { return }
        guard NotebookConfig.Attachments.isValidFolderName(name) else {
            errorMessage = String(localized: "“\(name)” can’t be used as a folder name.")
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
