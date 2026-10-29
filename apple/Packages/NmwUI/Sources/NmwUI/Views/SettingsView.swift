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

/// The Settings window: the settings of the selected notebook.
public struct SettingsView: View {
    @Bindable var library: Library

    public init(library: Library) {
        self.library = library
    }

    public var body: some View {
        Group {
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
            }
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

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
