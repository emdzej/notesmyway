//
//  NoteEditorView.swift
//  NmyUI
//
//  The editor for one note (notebook or standalone): the engine view bound
//  to a `NoteEditorModel`, plus the conflict and error bars and the
//  "Link to Note" picker.
//

import MarkdownEngine
import NmyCore
import SwiftUI

struct NoteEditorView: View {
    @Bindable var model: NoteEditorModel
    let root: URL?
    let previews: LinkPreviewStore?
    /// Images or previews changed; restyles the editor.
    let version: Int
    /// Notes the "Link to Note" picker offers; nil hides the picker (standalone files).
    let linkableNotes: (() -> [NoteSummary])?
    let onLink: (LinkAction) -> Void
    let onStoredFiles: @MainActor @Sendable ([URL]) -> Void

    @State private var controller = MarkdownEditorController()
    @State private var showingLinkPicker = false

    private var context: NoteContext { NoteContext(noteURL: model.url, root: root, previews: previews) }

    var body: some View {
        VStack(spacing: 0) {
            if model.conflict != nil { ConflictBar(model: model) }
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.yellow.opacity(0.15))
            }
            NativeTextViewWrapper(
                text: $model.text,
                configuration: EditorSetup.configuration(for: context, version: version),
                documentId: model.url.path,
                isEditable: model.isLoaded && model.errorMessage == nil,
                controller: controller,
                onDropFiles: EditorSetup.dropHandler(for: context, stored: onStoredFiles),
                onLinkClick: { destination in onLink(LinkAction.classify(destination, in: context)) }
            )
        }
        .task(id: model.url) { if !model.isLoaded { model.load() } }
        .onDisappear { model.flush() }
        .focusedSceneValue(\.linkToNote, linkableNotes == nil ? nil : LinkToNoteAction(noteURL: model.url) { showingLinkPicker = true })
        .sheet(isPresented: $showingLinkPicker) {
            if let linkableNotes {
                NoteLinkPicker(notes: linkableNotes()) { note in
                    showingLinkPicker = false
                    insertLink(to: note)
                }
            }
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

/// Fuzzy picker over the notebook's notes (Cmd-L).
struct NoteLinkPicker: View {
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
            TextField("Link to note…", text: $query)
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
