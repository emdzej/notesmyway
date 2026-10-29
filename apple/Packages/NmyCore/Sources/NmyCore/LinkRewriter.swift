//
//  LinkRewriter.swift
//  NmyCore
//
//  Keeps relative links working when files move (spec §6, "Renames"):
//  links *to* a moved file are pointed at its new place, and a moved note's
//  own relative links are adjusted for its new folder. Only destinations
//  that change are touched; everything else in the text stays as written.
//

import Foundation
import GRDB

/// A rewritten note, ready to save.
public struct NoteEdit: Equatable, Sendable {
    public let path: NotebookPath
    /// The text the edit was computed from; save with `NoteFile.write(_:replacing:)`
    /// against a snapshot of it so a concurrent change isn't overwritten.
    public let oldText: String
    public let newText: String
}

public enum LinkRewriter {

    /// `text` with its relative links updated after files moved.
    /// - Parameters:
    ///   - oldURL: where the note was (its links are resolved from here).
    ///   - newURL: where the note is now (new destinations are relative to it).
    ///   - moves: old → new location of every moved file.
    ///   - root: notebook root, for `/`-rooted links (kept rooted).
    /// - Returns: nil when nothing changes.
    public static func rewrite(_ text: String, from oldURL: URL, to newURL: URL, moves: [URL: URL], root: URL?) -> String? {
        let moves = Dictionary(uniqueKeysWithValues: moves.map { ($0.key.standardizedFileURL, $0.value.standardizedFileURL) })
        let noteMoved = oldURL.standardizedFileURL.deletingLastPathComponent() != newURL.standardizedFileURL.deletingLastPathComponent()
        var replacements: [(Range<String.Index>, String)] = []

        for occurrence in LinkScanner.occurrences(in: text) {
            guard case .file(let oldTarget, let fragment)? = LinkTarget.resolve(occurrence.destination, from: oldURL, root: root) else { continue }
            let newTarget = moves[oldTarget] ?? oldTarget
            let rooted = occurrence.destination.hasPrefix("/") || occurrence.destination.hasPrefix("</")
            // A rooted link only changes when its target moves.
            guard newTarget != oldTarget || (noteMoved && !rooted) else { continue }

            var path: String
            if rooted, let root, let notebookPath = NotebookPath(url: newTarget, root: root) {
                path = "/" + notebookPath.rawValue
            } else {
                path = LinkPath.relative(from: newURL, to: newTarget)
            }
            path = LinkPath.encode(path)
            if let fragment { path += "#" + (fragment.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? fragment) }
            if String(text[occurrence.range]) != path { replacements.append((occurrence.range, path)) }
        }
        guard !replacements.isEmpty else { return nil }

        var result = text
        for (range, replacement) in replacements.sorted(by: { $0.0.lowerBound > $1.0.lowerBound }) {
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }
}

extension NotebookIndex {

    /// Edits that keep links working after `moves` (old → new notebook path):
    /// every note linking to a moved file, plus each moved note itself.
    /// Notes are read from their *new* location. Nothing is written.
    public func linkEdits(for moves: [NotebookPath: NotebookPath]) throws -> [NoteEdit] {
        guard !moves.isEmpty else { return [] }
        let urlMoves = Dictionary(uniqueKeysWithValues: moves.map { (notebook.url(for: $0.key), notebook.url(for: $0.value)) })

        // Notes to revisit, keyed by their current path, with their old path.
        var affected: [NotebookPath: NotebookPath] = [:]
        for (old, new) in moves where FileKind(path: new) == .note { affected[new] = old }
        for old in moves.keys {
            for source in try linkSources(to: old) where affected[moves[source] ?? source] == nil {
                affected[moves[source] ?? source] = source
            }
        }

        var edits: [NoteEdit] = []
        for (current, old) in affected.sorted(by: { $0.key < $1.key }) {
            guard let text = try? NoteFile(url: notebook.url(for: current)).read().text,
                  let rewritten = LinkRewriter.rewrite(text, from: notebook.url(for: old), to: notebook.url(for: current),
                                                       moves: urlMoves, root: notebook.root) else { continue }
            edits.append(NoteEdit(path: current, oldText: text, newText: rewritten))
        }
        return edits
    }

    /// Paths of notes with a link resolving to `path`.
    func linkSources(to path: NotebookPath) throws -> [NotebookPath] {
        try db.read { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT f.path FROM links l JOIN files f ON f.id = l.src_id WHERE l.target_path = ?
                """, arguments: [path.rawValue]).compactMap(NotebookPath.init)
        }
    }
}
