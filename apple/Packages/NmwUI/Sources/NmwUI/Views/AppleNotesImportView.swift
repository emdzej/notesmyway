//
//  AppleNotesImportView.swift
//  NmwUI
//
//  File › Import from Apple Notes… (macOS): asks for access to Notes' data
//  folder, shows what's there, and imports it into a folder of the current
//  notebook. Notes' own files are only read.
//

#if os(macOS)
import AppKit
import NmwCore
import SwiftUI

struct AppleNotesImportView: View {
    let session: NotebookSession
    @Environment(\.dismiss) private var dismiss

    private enum Step {
        case start
        case loading
        case ready(AppleNotesLibrary)
        case importing(done: Int, total: Int)
        case finished(AppleNotesImporter.Report)
    }

    @State private var step = Step.start
    @State private var folderName = "Apple Notes"
    @State private var errorMessage: String?
    @State private var access: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Import from Apple Notes", systemImage: "square.and.arrow.down.on.square")
                .font(.title3.weight(.semibold))
            content
            if let errorMessage {
                Text(errorMessage).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                buttons
            }
        }
        .padding(24)
        .frame(width: 460)
        .onDisappear { access?.stopAccessingSecurityScopedResource() }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .start:
            Text("Notes my Way reads Apple Notes’ data folder and writes each note as a Markdown file in “\(session.name)”. Apple Notes isn’t changed.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Next, choose the “group.com.apple.notes” folder. It’s already selected in the window that opens; click Open.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        case .loading:
            ProgressView("Reading Apple Notes…").frame(maxWidth: .infinity)
        case .ready(let library):
            let importer = AppleNotesImporter(library: library, notebookRoot: session.notebook.root, layout: session.config.attachments)
            let locked = library.notes.filter { $0.locked && !$0.deleted }.count
            let folders = library.folders.filter { !$0.isSpecial }.count
            Text("\(importer.importableCount) notes in \(folders) folders.")
            if locked > 0 {
                Text("\(locked) locked notes will be skipped: unlock them in Apple Notes first to import them.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            LabeledContent("Into the folder") {
                TextField("Folder", text: $folderName).frame(width: 200)
            }
            Text("Notes keep their folders, dates, pinned state, checklists, tables and attachments.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
            Button("Choose Folder…") { choose() }.keyboardShortcut(.defaultAction)
        case .loading, .importing:
            Button("Cancel", role: .cancel) { dismiss() }.disabled(true)
        case .ready(let library):
            Button("Cancel", role: .cancel) { dismiss() }
            Button("Import") { run(library) }
                .keyboardShortcut(.defaultAction)
                .disabled(!NotebookConfig.Attachments.isValidFolderName(folderName))
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

    private func summary(_ report: AppleNotesImporter.Report) -> String {
        var parts: [String] = []
        if report.locked > 0 { parts.append("\(report.locked) locked notes were skipped.") }
        if report.tables > 0 { parts.append("\(report.tables) tables couldn’t be converted; their notes say where they were.") }
        if report.missingAttachments > 0 { parts.append("\(report.missingAttachments) attachments weren’t found (not downloaded from iCloud yet?).") }
        if !report.failures.isEmpty { parts.append("Couldn’t read: \(report.failures.prefix(5).joined(separator: ", ")).") }
        return parts.joined(separator: " ")
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = AppleNotesLibrary.defaultFolder
        panel.message = "Choose Apple Notes’ data folder, “group.com.apple.notes”."
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        errorMessage = nil
        access?.stopAccessingSecurityScopedResource()
        access = url.startAccessingSecurityScopedResource() ? url : nil
        step = .loading
        Task {
            let result = await Task.detached { Result { try AppleNotesLibrary(folder: url) } }.value
            switch result {
            case .success(let library):
                step = .ready(library)
            case .failure(let error):
                errorMessage = error.localizedDescription
                step = .start
            }
        }
    }

    private func run(_ library: AppleNotesLibrary) {
        let importer = AppleNotesImporter(library: library, notebookRoot: session.notebook.root, layout: session.config.attachments)
        let destination = uniqueFolder(named: folderName.trimmingCharacters(in: .whitespaces))
        step = .importing(done: 0, total: importer.importableCount)
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

    /// "Apple Notes", or "Apple Notes 2" if that folder is already there.
    private func uniqueFolder(named name: String) -> URL {
        let root = session.notebook.root
        var candidate = root.appending(path: name, directoryHint: .isDirectory)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = root.appending(path: "\(name) \(n)", directoryHint: .isDirectory)
            n += 1
        }
        return candidate
    }
}
#endif
