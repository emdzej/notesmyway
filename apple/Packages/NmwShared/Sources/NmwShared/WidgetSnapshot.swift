//
//  WidgetSnapshot.swift
//  NmwShared
//
//  A small summary of the user's notebooks, written by the app whenever an
//  index changes and read by the widgets and the share extension (which
//  can't open the notebooks themselves: their folder access belongs to the app).
//

import Foundation

public struct WidgetSnapshot: Codable, Equatable, Sendable {

    public struct Note: Codable, Equatable, Sendable, Identifiable {
        public var notebookID: String
        /// Path in the notebook, `Projects/Idea.md`.
        public var path: String
        public var title: String
        public var snippet: String
        public var modified: Date
        public var pinned: Bool

        public var id: String { "\(notebookID)/\(path)" }

        public init(notebookID: String, path: String, title: String, snippet: String, modified: Date, pinned: Bool) {
            self.notebookID = notebookID
            self.path = path
            self.title = title
            self.snippet = snippet
            self.modified = modified
            self.pinned = pinned
        }

        public var link: URL { AppLink.open(notebook: notebookID, path: path).url }
    }

    public struct Notebook: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var pinned: [Note]
        /// Most recently modified first.
        public var recent: [Note]

        public init(id: String, name: String, pinned: [Note], recent: [Note]) {
            self.id = id
            self.name = name
            self.pinned = pinned
            self.recent = recent
        }
    }

    public var generated: Date
    public var notebooks: [Notebook]
    /// The notebook the app has selected; first in the share extension's list.
    public var selectedNotebookID: String?

    public init(generated: Date = Date(), notebooks: [Notebook] = [], selectedNotebookID: String? = nil) {
        self.generated = generated
        self.notebooks = notebooks
        self.selectedNotebookID = selectedNotebookID
    }

    /// Pinned notes of every notebook, most recent first.
    public var allPinned: [Note] { notebooks.flatMap(\.pinned).sorted { $0.modified > $1.modified } }

    /// Recent notes of every notebook, most recent first.
    public var allRecent: [Note] { notebooks.flatMap(\.recent).sorted { $0.modified > $1.modified } }

    // MARK: Storage

    public static func load(from url: URL = AppGroup.snapshotURL) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    public func save(to url: URL = AppGroup.snapshotURL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
