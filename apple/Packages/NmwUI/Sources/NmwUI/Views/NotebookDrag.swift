//
//  NotebookDrag.swift
//  NmwUI
//
//  Notes and folders dragged onto a sidebar folder move there. A single
//  note also drags out of the app (Finder, Mail) as its .md file.
//

import CoreTransferable
import NmwCore
import UniformTypeIdentifiers

extension UTType {
    /// In-app drags; declared in the app's Info.plist.
    static let nmwItems = UTType(exportedAs: "pl.emdzej.notesmyway.items")
}

struct NotebookDragItem: Codable, Transferable {
    /// The notebook's folder: a drop only moves items within their own notebook.
    let notebook: String
    let paths: [String]
    /// The note's file, for drags out of the app (one note only).
    let fileURL: URL?

    init(notebook: Notebook, paths: [NotebookPath]) {
        self.notebook = notebook.root.standardizedFileURL.path
        self.paths = paths.map(\.rawValue)
        fileURL = paths.count == 1 && paths[0].rawValue.lowercased().hasSuffix(".md") ? notebook.url(for: paths[0]) : nil
    }

    func items(in notebook: Notebook) -> [NotebookPath] {
        guard self.notebook == notebook.root.standardizedFileURL.path else { return [] }
        return paths.compactMap(NotebookPath.init)
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .nmwItems)
        FileRepresentation(exportedContentType: NoteExport.markdownType) { item in
            SentTransferredFile(item.fileURL!)
        }
        .exportingCondition { $0.fileURL != nil }
    }
}
