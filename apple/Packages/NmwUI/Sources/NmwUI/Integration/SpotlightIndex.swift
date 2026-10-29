//
//  SpotlightIndex.swift
//  NmwUI
//
//  Notes in Spotlight (spec §5.1): one searchable item per note, in a
//  domain per notebook, identified as `<notebook id>/<path>`. Items are
//  built off the main thread (each needs the file's text for its tags and
//  content).
//

import CoreSpotlight
import Foundation
import NmwCore
import UniformTypeIdentifiers

enum SpotlightIndex {

    static func identifier(notebookID: String, path: NotebookPath) -> String { "\(notebookID)/\(path.rawValue)" }

    /// `(notebook id, path)` of an item identifier. Notebook ids are hex, so the first `/` separates them.
    static func parse(_ identifier: String) -> (notebookID: String, path: NotebookPath)? {
        guard let slash = identifier.firstIndex(of: "/"),
              let path = NotebookPath(String(identifier[identifier.index(after: slash)...])) else { return nil }
        return (String(identifier[..<slash]), path)
    }

    /// Adds or replaces the items for `paths`.
    static func index(_ paths: [NotebookPath], in notebook: Notebook, notebookName: String) async {
        guard CSSearchableIndex.isIndexingAvailable(), !paths.isEmpty else { return }
        let id = notebook.localID
        // Items aren't Sendable: built and handed to Spotlight in the same task.
        await Task.detached(priority: .utility) {
            for start in stride(from: 0, to: paths.count, by: 200) {
                let items = paths[start..<min(start + 200, paths.count)].compactMap { path in
                    item(for: path, in: notebook, notebookID: id, notebookName: notebookName)
                }
                try? await CSSearchableIndex.default().indexSearchableItems(items)
            }
        }.value
    }

    static func remove(_ paths: [NotebookPath], notebookID: String) async {
        guard CSSearchableIndex.isIndexingAvailable(), !paths.isEmpty else { return }
        try? await CSSearchableIndex.default().deleteSearchableItems(
            withIdentifiers: paths.map { identifier(notebookID: notebookID, path: $0) })
    }

    static func removeNotebook(_ notebookID: String) async {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        try? await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [notebookID])
    }

    private static func item(for path: NotebookPath, in notebook: Notebook, notebookID: String, notebookName: String) -> CSSearchableItem? {
        let url = notebook.url(for: path)
        guard let snapshot = try? NoteFile(url: url).read() else { return nil }
        let meta = NoteMetadata(markdown: snapshot.text, fileName: path.stem)
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = meta.title
        attributes.displayName = meta.title
        attributes.contentDescription = meta.snippet
        attributes.textContent = String(Frontmatter.body(of: snapshot.text).prefix(20_000))
        attributes.keywords = meta.tags + [notebookName]
        attributes.contentModificationDate = snapshot.modified
        attributes.containerDisplayName = notebookName
        attributes.containerTitle = notebookName
        return CSSearchableItem(uniqueIdentifier: identifier(notebookID: notebookID, path: path),
                                domainIdentifier: notebookID, attributeSet: attributes)
    }
}
