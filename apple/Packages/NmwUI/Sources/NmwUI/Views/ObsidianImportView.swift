//
//  ObsidianImportView.swift
//  NmwUI
//
//  Import from Obsidian…: asks for a vault folder, shows what's in it and
//  how much it is, and copies it into a folder of the current notebook with
//  wikilinks turned into standard links and attachments moved to the
//  notebook's attachment folders. The vault is only read.
//

import NmwCore
import SwiftUI

struct ObsidianImportView: View {
    let session: NotebookSession
    @Environment(\.dismiss) private var dismiss

    private enum Step {
        case start
        case loading
        case ready(ObsidianImporter.Vault)
        case importing(done: Int, total: Int)
        case finished(ObsidianImporter.Report)
    }

    @State private var step = Step.start
    @State private var folderName = "Obsidian"
    @State private var errorMessage: String?
    @State private var access: URL?
    @State private var isPicking = false

    var body: some View {
        #if os(macOS)
        form.padding(24).frame(width: 460)
        #else
        NavigationStack {
            ScrollView { form.padding() }
                .navigationTitle("Import from Obsidian")
                .navigationBarTitleDisplayMode(.inline)
        }
        #endif
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            #if os(macOS)
            Label("Import from Obsidian", systemImage: "square.and.arrow.down.on.square")
                .font(.title3.weight(.semibold))
            #endif
            content
            if let errorMessage {
                Text(errorMessage).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                buttons
            }
        }
        .fileImporter(isPresented: $isPicking, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { load(url) }
        }
        .onDisappear { access?.stopAccessingSecurityScopedResource() }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .start:
            Text("Notes my Way copies an Obsidian vault into “\(session.name)”: notes keep their folders and dates, wikilinks become standard Markdown links, and attachments move to this notebook’s attachment folders. The vault isn’t changed.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Next, choose the vault’s folder.")
                .foregroundStyle(.secondary)
        case .loading:
            ProgressView("Reading the vault…").frame(maxWidth: .infinity)
        case .ready(let vault):
            Text("\(vault.notes.count) notes and \(vault.files.count) other files, about \(ImportSize.format(vault.size)).")
            if !vault.hasSettings {
                Text("This folder has no Obsidian settings (.obsidian), so it may not be a vault; its notes can still be imported.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let warning = ImportSize.spaceWarning(vault.size, at: session.notebook.root) {
                Text(warning).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            LabeledContent("Into the folder") {
                TextField("Folder", text: $folderName)
                    #if os(macOS)
                    .frame(width: 200)
                    #endif
            }
        case .importing(let done, let total):
            ProgressView(value: Double(done), total: Double(max(total, 1))) {
                Text("Importing \(done) of \(total)…")
            }
        case .finished(let report):
            Text("Imported \(report.imported) notes into “\(report.destination?.lastPathComponent ?? folderName)”.")
            let notes = summary(report)
            if !notes.isEmpty {
                Text(notes).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var buttons: some View {
        switch step {
        case .start:
            Button("Cancel", role: .cancel) { dismiss() }
            Button("Choose Vault…") { isPicking = true }.keyboardShortcut(.defaultAction)
        case .loading, .importing:
            Button("Cancel", role: .cancel) { dismiss() }.disabled(true)
        case .ready(let vault):
            Button("Cancel", role: .cancel) { dismiss() }
            Button("Import") { run(vault) }
                .keyboardShortcut(.defaultAction)
                .disabled(!NotebookConfig.Attachments.isValidFolderName(folderName) || vault.notes.isEmpty)
        case .finished(let report):
            Button("Show Notes") {
                if let destination = report.destination, let path = session.path(for: destination) {
                    session.scope = .folder(path)
                }
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private func summary(_ report: ObsidianImporter.Report) -> String {
        var parts: [String] = []
        if report.attachments > 0 { parts.append("\(report.attachments) attachments moved to attachment folders.") }
        if report.otherFiles > 0 { parts.append("\(report.otherFiles) files no note links to were copied where they were.") }
        if report.embeddedNotes > 0 { parts.append("\(report.embeddedNotes) embedded notes became links.") }
        if report.unresolvedLinks > 0 { parts.append("\(report.unresolvedLinks) links point at notes or files that aren’t in the vault; they were left as written.") }
        let failed = report.failures.prefix(5).joined(separator: ", ")
        if !report.failures.isEmpty { parts.append(String(localized: "Couldn’t copy: \(failed).")) }
        return parts.joined(separator: " ")
    }

    private func load(_ url: URL) {
        let root = session.notebook.root.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        let vaultPath = url.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        // Importing a folder that holds this notebook would copy the notebook into itself.
        guard !root.hasPrefix(vaultPath) else {
            errorMessage = String(localized: "That folder contains this notebook. Choose the vault’s own folder.")
            return
        }
        errorMessage = nil
        access?.stopAccessingSecurityScopedResource()
        access = url.startAccessingSecurityScopedResource() ? url : nil
        step = .loading
        Task {
            let vault = await Task.detached { ObsidianImporter.scan(url) }.value
            step = .ready(vault)
        }
    }

    private func run(_ vault: ObsidianImporter.Vault) {
        let importer = ObsidianImporter(vault: vault, notebookRoot: session.notebook.root, layout: session.config.attachments)
        let destination = ImportSize.uniqueFolder(named: folderName.trimmingCharacters(in: .whitespaces), in: session.notebook.root)
        step = .importing(done: 0, total: vault.notes.count)
        Task {
            let report = await Task.detached {
                importer.run(into: destination) { done, total in
                    Task { @MainActor in step = .importing(done: done, total: total) }
                }
            }.value
            await session.reindex(report.files.compactMap { session.path(for: $0) })
            session.refresh()
            step = .finished(report)
        }
    }
}
