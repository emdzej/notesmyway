//
//  NotebookIndex.swift
//  NmyCore
//
//  The per-device SQLite index of a notebook (spec §6): files, note metadata,
//  tags, links, and full-text search. Derived from the files, never synced,
//  safe to delete. Standalone files aren't indexed.
//

import Foundation
import GRDB

public struct NoteSummary: Hashable, Sendable, Identifiable {
    public let id: Int64
    public let path: NotebookPath
    public let title: String
    public let snippet: String
    public let pinned: Bool
    public let created: Date?
    public let modified: Date
    /// First image destination as written in the note.
    public let firstImage: String?
}

public struct TagCount: Hashable, Sendable {
    public let tag: String
    public let count: Int
}

public enum NoteSort: Sendable {
    case modified, created, title
}

/// What the index knows about a file, for change detection.
public struct IndexedFile: Hashable, Sendable {
    public let id: Int64
    public let kind: FileKind
    public let size: Int
    public let mtime: Int64
    public let hash: String?
}

public final class NotebookIndex: Sendable {
    public let notebook: Notebook
    let db: DatabaseQueue

    /// Opens (or creates) the index at `url`; nil keeps it in memory.
    public init(notebook: Notebook, at url: URL?) throws {
        self.notebook = notebook
        if let url {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            db = try DatabaseQueue(path: url.path)
        } else {
            db = try DatabaseQueue()
        }
        try Self.migrator.migrate(db)
    }

    /// `Application Support/nmy/index/<notebook-id>.sqlite` (spec §6).
    public static func defaultLocation(for notebook: Notebook) throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "nmy/index/\(notebook.localID).sqlite")
    }

    // MARK: Schema

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE files (
                  id INTEGER PRIMARY KEY,
                  path TEXT UNIQUE NOT NULL,
                  kind TEXT NOT NULL,
                  hash TEXT,
                  size INTEGER NOT NULL,
                  mtime INTEGER NOT NULL,
                  downloaded INTEGER NOT NULL DEFAULT 1
                );
                CREATE INDEX files_hash ON files(hash);
                CREATE TABLE notes (
                  file_id INTEGER PRIMARY KEY REFERENCES files(id) ON DELETE CASCADE,
                  title TEXT NOT NULL,
                  snippet TEXT NOT NULL,
                  pinned INTEGER NOT NULL DEFAULT 0,
                  created INTEGER,
                  first_image TEXT
                );
                CREATE TABLE tags (
                  file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
                  tag TEXT NOT NULL
                );
                CREATE INDEX tags_tag ON tags(tag);
                CREATE INDEX tags_file ON tags(file_id);
                CREATE TABLE links (
                  src_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
                  target TEXT NOT NULL,
                  target_path TEXT,
                  kind TEXT NOT NULL
                );
                CREATE INDEX links_target_path ON links(target_path);
                CREATE INDEX links_src ON links(src_id);
                CREATE TABLE link_previews (
                  url TEXT PRIMARY KEY,
                  title TEXT,
                  summary TEXT,
                  icon_path TEXT,
                  image_path TEXT,
                  fetched INTEGER,
                  status TEXT
                );
                CREATE VIRTUAL TABLE notes_fts USING fts5(title, body, tokenize = 'unicode61 remove_diacritics 2');
                """)
        }
        migrator.registerMigration("v2-preview-subtitle") { db in
            try db.execute(sql: "ALTER TABLE link_previews ADD COLUMN subtitle TEXT")
        }
        return migrator
    }

    // MARK: Writing

    public func indexedFiles() throws -> [NotebookPath: IndexedFile] {
        try db.read { db in
            var result: [NotebookPath: IndexedFile] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT id, path, kind, size, mtime, hash FROM files") {
                guard let path = NotebookPath(row["path"]) else { continue }
                result[path] = IndexedFile(
                    id: row["id"], kind: FileKind(rawValue: row["kind"]) ?? .other,
                    size: row["size"], mtime: row["mtime"], hash: row["hash"]
                )
            }
            return result
        }
    }

    /// Inserts or replaces a file and, for notes, its metadata, tags, links and search text.
    public func upsert(_ file: ScannedFile, hash: String?, note: NoteMetadata?) throws {
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO files (path, kind, hash, size, mtime) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(path) DO UPDATE SET kind = excluded.kind, hash = excluded.hash,
                  size = excluded.size, mtime = excluded.mtime
                """, arguments: [file.path.rawValue, file.kind.rawValue, hash, file.size, file.mtime])
            let id = try Int64.fetchOne(db, sql: "SELECT id FROM files WHERE path = ?", arguments: [file.path.rawValue])!
            try Self.clearNoteRows(db, id: id)
            guard let note else { return }

            try db.execute(sql: """
                INSERT INTO notes (file_id, title, snippet, pinned, created, first_image) VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [id, note.title, note.snippet, note.pinned,
                                 note.created.map { Int64($0.timeIntervalSince1970 * 1000) }, note.firstImage])
            for tag in note.tags {
                try db.execute(sql: "INSERT INTO tags (file_id, tag) VALUES (?, ?)", arguments: [id, tag])
            }
            let noteURL = notebook.url(for: file.path)
            for link in note.links {
                let targetPath: String? = {
                    guard case .file(let url, _)? = LinkTarget.resolve(link.destination, from: noteURL, root: notebook.root) else { return nil }
                    return notebook.path(for: url)?.rawValue
                }()
                try db.execute(sql: "INSERT INTO links (src_id, target, target_path, kind) VALUES (?, ?, ?, ?)",
                               arguments: [id, link.destination, targetPath, link.kind.rawValue])
            }
            try db.execute(sql: "INSERT INTO notes_fts (rowid, title, body) VALUES (?, ?, ?)",
                           arguments: [id, note.title, note.searchText])
        }
    }

    public func remove(_ paths: [NotebookPath]) throws {
        guard !paths.isEmpty else { return }
        try db.write { db in
            for path in paths {
                guard let id = try Int64.fetchOne(db, sql: "SELECT id FROM files WHERE path = ?", arguments: [path.rawValue]) else { continue }
                try Self.clearNoteRows(db, id: id)
                try db.execute(sql: "DELETE FROM files WHERE id = ?", arguments: [id])
            }
        }
    }

    private static func clearNoteRows(_ db: Database, id: Int64) throws {
        try db.execute(sql: "DELETE FROM notes WHERE file_id = ?", arguments: [id])
        try db.execute(sql: "DELETE FROM tags WHERE file_id = ?", arguments: [id])
        try db.execute(sql: "DELETE FROM links WHERE src_id = ?", arguments: [id])
        try db.execute(sql: "DELETE FROM notes_fts WHERE rowid = ?", arguments: [id])
    }

    // MARK: Reading

    private static let summaryColumns = """
        f.id, f.path, f.mtime, n.title, n.snippet, n.pinned, n.created, n.first_image
        """

    private static func summary(_ row: Row) -> NoteSummary? {
        guard let path = NotebookPath(row["path"]) else { return nil }
        let created: Int64? = row["created"]
        return NoteSummary(
            id: row["id"], path: path, title: row["title"], snippet: row["snippet"], pinned: row["pinned"],
            created: created.map { Date(timeIntervalSince1970: Double($0) / 1000) },
            modified: Date(timeIntervalSince1970: Double(row["mtime"] as Int64) / 1000),
            firstImage: row["first_image"]
        )
    }

    private static func orderBy(_ sort: NoteSort) -> String {
        switch sort {
        case .modified: return "n.pinned DESC, f.mtime DESC"
        case .created: return "n.pinned DESC, COALESCE(n.created, f.mtime) DESC"
        case .title: return "n.pinned DESC, n.title COLLATE NOCASE ASC"
        }
    }

    /// Notes in `folder` (the whole notebook when nil), pinned first.
    public func notes(in folder: NotebookPath? = nil, recursive: Bool = true, sortedBy sort: NoteSort = .modified) throws -> [NoteSummary] {
        try db.read { db in
            var sql = "SELECT \(Self.summaryColumns) FROM notes n JOIN files f ON f.id = n.file_id"
            var arguments: StatementArguments = []
            if let folder {
                let prefix = Self.escapeLike(folder.rawValue) + "/"
                sql += " WHERE f.path LIKE ? ESCAPE '\\'"
                arguments += [prefix + "%"]
                if !recursive {
                    sql += " AND instr(substr(f.path, ?), '/') = 0"
                    arguments += [folder.rawValue.unicodeScalars.count + 2]   // substr counts code points
                }
            } else if !recursive {
                sql += " WHERE instr(f.path, '/') = 0"
            }
            sql += " ORDER BY \(Self.orderBy(sort))"
            return try Row.fetchAll(db, sql: sql, arguments: arguments).compactMap(Self.summary)
        }
    }

    public func note(at path: NotebookPath) throws -> NoteSummary? {
        try db.read { db in
            try Row.fetchOne(db, sql: "SELECT \(Self.summaryColumns) FROM notes n JOIN files f ON f.id = n.file_id WHERE f.path = ?",
                             arguments: [path.rawValue]).flatMap(Self.summary)
        }
    }

    /// Notes linking to `path`.
    public func backlinks(to path: NotebookPath) throws -> [NoteSummary] {
        try db.read { db in
            try Row.fetchAll(db, sql: """
                SELECT DISTINCT \(Self.summaryColumns) FROM links l
                JOIN files f ON f.id = l.src_id JOIN notes n ON n.file_id = f.id
                WHERE l.target_path = ? AND f.path != ?
                ORDER BY n.title COLLATE NOCASE
                """, arguments: [path.rawValue, path.rawValue]).compactMap(Self.summary)
        }
    }

    public func tags() throws -> [TagCount] {
        try db.read { db in
            try Row.fetchAll(db, sql: "SELECT tag, COUNT(DISTINCT file_id) AS c FROM tags GROUP BY tag ORDER BY tag")
                .map { TagCount(tag: $0["tag"], count: $0["c"]) }
        }
    }

    /// Notes tagged `tag` or any `tag/…` below it.
    public func notes(taggedWith tag: String, sortedBy sort: NoteSort = .modified) throws -> [NoteSummary] {
        let tag = Frontmatter.tagName(tag)
        return try db.read { db in
            try Row.fetchAll(db, sql: """
                SELECT \(Self.summaryColumns) FROM notes n JOIN files f ON f.id = n.file_id
                WHERE f.id IN (SELECT file_id FROM tags WHERE tag = ? OR tag LIKE ? ESCAPE '\\')
                ORDER BY \(Self.orderBy(sort))
                """, arguments: [tag, Self.escapeLike(tag) + "/%"]).compactMap(Self.summary)
        }
    }

    /// Full-text search with `tag:x` and `path:Folder` filters; words match
    /// as prefixes and all must appear. Best matches first.
    public func search(_ query: String, limit: Int = 100) throws -> [NoteSummary] {
        let parsed = SearchQuery(query)
        guard !parsed.isEmpty else { return [] }
        return try db.read { db in
            var sql = "SELECT \(Self.summaryColumns) FROM notes n JOIN files f ON f.id = n.file_id"
            var conditions: [String] = []
            var arguments: StatementArguments = []
            if let match = parsed.ftsMatch {
                sql += " JOIN notes_fts ON notes_fts.rowid = f.id"
                conditions.append("notes_fts MATCH ?")
                arguments += [match]
            }
            for tag in parsed.tags {
                conditions.append("f.id IN (SELECT file_id FROM tags WHERE tag = ? OR tag LIKE ? ESCAPE '\\')")
                arguments += [tag, Self.escapeLike(tag) + "/%"]
            }
            for path in parsed.paths {
                conditions.append("f.path LIKE ? ESCAPE '\\'")
                arguments += [Self.escapeLike(path) + "%"]
            }
            sql += " WHERE " + conditions.joined(separator: " AND ")
            sql += parsed.ftsMatch != nil ? " ORDER BY bm25(notes_fts, 5.0, 1.0)" : " ORDER BY f.mtime DESC"
            sql += " LIMIT \(limit)"
            return try Row.fetchAll(db, sql: sql, arguments: arguments).compactMap(Self.summary)
        }
    }

    /// File id and hash lookups, for rename detection.
    public func paths(withHash hash: String) throws -> [NotebookPath] {
        try db.read { db in
            try String.fetchAll(db, sql: "SELECT path FROM files WHERE hash = ?", arguments: [hash]).compactMap(NotebookPath.init)
        }
    }

    static func escapeLike(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
    }
}

/// A parsed search box query.
struct SearchQuery {
    var words: [String] = []
    var tags: [String] = []
    var paths: [String] = []

    init(_ query: String) {
        for token in Self.tokens(query) {
            let lower = token.lowercased()
            if lower.hasPrefix("tag:"), token.count > 4 {
                tags.append(Frontmatter.tagName(String(token.dropFirst(4))))
            } else if lower.hasPrefix("path:"), token.count > 5 {
                paths.append(String(token.dropFirst(5)).precomposedStringWithCanonicalMapping)
            } else if lower.hasPrefix("#"), token.count > 1 {
                tags.append(Frontmatter.tagName(token))
            } else {
                words.append(token)
            }
        }
    }

    var isEmpty: Bool { words.isEmpty && tags.isEmpty && paths.isEmpty }

    /// Each word quoted (so FTS syntax in user input is inert) and prefix-matched.
    var ftsMatch: String? {
        let terms = words.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"*" }
        return terms.isEmpty ? nil : terms.joined(separator: " ")
    }

    /// Whitespace-separated, with `"quoted phrases"` (and `path:"a b"`) kept together.
    static func tokens(_ query: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quoted = false
        for c in query {
            if c == "\"" { quoted.toggle(); continue }
            if c.isWhitespace, !quoted {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(c)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}
