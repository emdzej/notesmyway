//
//  ShareView.swift
//  NmwShare
//
//  The share sheet: pick a notebook and whether the content becomes a new
//  note or goes to the notebook's Inbox note.
//

import NmwShared
import SwiftUI

struct ShareView: View {
    let load: @MainActor () async -> ShareContent
    let finish: (_ saved: Bool) -> Void

    @State private var content: ShareContent?
    @State private var notebooks: [WidgetSnapshot.Notebook] = []
    @State private var notebookID: String?
    @State private var destination: ShareJob.Destination = .newNote
    @State private var title = ""
    @State private var comment = ""
    @State private var errorMessage: String?
    @AppStorage("nmw.share.destination") private var lastDestination = ShareJob.Destination.newNote.rawValue

    var body: some View {
        NavigationStack {
            Form {
                if let content {
                    Section {
                        Text(content.isEmpty ? "Nothing to save." : content.summary)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    Section {
                        if notebooks.isEmpty {
                            Text("Open Notes my Way and add a notebook first.").foregroundStyle(.secondary)
                        } else {
                            Picker("Notebook", selection: $notebookID) {
                                ForEach(notebooks) { Text($0.name).tag(Optional($0.id)) }
                            }
                        }
                        Picker("Save as", selection: $destination) {
                            Text("New Note").tag(ShareJob.Destination.newNote)
                            Text("Add to Inbox").tag(ShareJob.Destination.inbox)
                        }
                    }
                    Section {
                        TextField(destination == .newNote ? "Title" : "Title (optional)", text: $title)
                        TextField("Comment", text: $comment, axis: .vertical).lineLimit(2...5)
                    } footer: {
                        Text(destination == .inbox ? "Added to Inbox.md in the notebook, under today’s date." : "The note is created when Notes my Way opens.")
                    }
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                } else {
                    ProgressView()
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Notes my Way")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { content?.discard(); finish(false) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(content?.isEmpty ?? true || notebooks.isEmpty)
                }
            }
        }
        .tint(Color("AccentColor"))
        .task {
            let snapshot = WidgetSnapshot.load()
            notebooks = snapshot?.notebooks ?? []
            notebookID = snapshot?.selectedNotebookID.flatMap { id in notebooks.first { $0.id == id }?.id } ?? notebooks.first?.id
            destination = ShareJob.Destination(rawValue: lastDestination) ?? .newNote
            let loaded = await load()
            content = loaded
            title = loaded.suggestedTitle
        }
        #if os(macOS)
        .frame(width: 420, height: 380)
        #endif
    }

    private func save() {
        guard let content else { return }
        do {
            try content.queue(notebookID: notebookID, destination: destination, title: title, comment: comment)
            lastDestination = destination.rawValue
            content.discard()
            finish(true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
