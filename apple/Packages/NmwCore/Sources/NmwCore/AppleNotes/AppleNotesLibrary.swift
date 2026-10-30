//
//  AppleNotesLibrary.swift
//  NmwCore
//
//  Reads Apple Notes' data folder (`~/Library/Group Containers/
//  group.com.apple.notes`): accounts, folders, notes and attachments from
//  `NoteStore.sqlite`, and attachment files from `Accounts/<id>/Media` and
//  `FallbackImages`. The database is copied first (with its WAL), so Notes
//  can keep running and nothing in its folder is ever written.
//
//  The schema is Core Data's: every object is a row of
//  `ZICCLOUDSYNCINGOBJECT`, told apart by `Z_ENT` (see `Z_PRIMARYKEY`), and
//  column names carry numeric suffixes that differ between macOS versions,
//  so columns are looked up rather than assumed.
//

import Foundation
import GRDB

public struct AppleNotesLibrary: Sendable {
    public struct Account: Sendable, Equatable {
        public let id: Int64
        public let identifier: String
        public let name: String
    }

    public struct Folder: Sendable, Equatable {
        public let id: Int64
        public let identifier: String
        public let name: String
        public let parentID: Int64?
        public let accountID: Int64?
        /// Recently Deleted, or a smart folder: not imported.
        public let isSpecial: Bool
    }

    public struct Note: Sendable, Equatable {
        public let id: Int64
        public let identifier: String
        public let title: String
        public let folderID: Int64?
        public let created: Date?
        public let modified: Date?
        public let pinned: Bool
        /// Locked notes are encrypted; they're skipped.
        public let locked: Bool
        public let deleted: Bool
        /// The gzipped protobuf body; nil if the note has none.
        public let data: Data?
    }

    public struct Attachment: Sendable, Equatable {
        public let id: Int64
        public let identifier: String
        public let typeUTI: String
        public let title: String?
        public let url: String?
        /// Inline attachments' text (`#tag`, `@name`, a linked note's title).
        public let altText: String?
        /// Inline note links: `applenotes:note/<identifier>…`.
        public let token: String?
        public let mediaID: Int64?
        public let parentID: Int64?
        /// Tables: gzipped CRDT data.
        public let mergeableData: Data?
    }

    public struct Media: Sendable, Equatable {
        public let id: Int64
        public let identifier: String
        public let fileName: String?
    }

    public enum Error: Swift.Error, LocalizedError, Equatable {
        case noDatabase
        case unreadable(String)

        public var errorDescription: String? {
            switch self {
            case .noDatabase: "The folder doesn’t contain Apple Notes’ database (NoteStore.sqlite)."
            case .unreadable(let reason): "Apple Notes’ database couldn’t be read: \(reason)"
            }
        }
    }

    /// The folder holding `NoteStore.sqlite`.
    public let root: URL
    public let accounts: [Account]
    public let folders: [Folder]
    public let notes: [Note]
    public let attachments: [String: Attachment]
    public let media: [Int64: Media]

    #if os(macOS)
    /// Where Notes keeps its data on this Mac (the user still has to grant
    /// access). The real home folder: in the sandbox, `homeDirectoryForCurrentUser`
    /// is the app's container.
    public static var defaultFolder: URL {
        let home = getpwuid(getuid())?.pointee.pw_dir.map { String(cString: $0) } ?? NSHomeDirectory()
        return URL(filePath: home, directoryHint: .isDirectory)
            .appending(path: "Library/Group Containers/group.com.apple.notes", directoryHint: .isDirectory)
    }
    #endif

    /// Reads everything except attachment files.
    public init(folder: URL) throws {
        let source = folder.appending(path: "NoteStore.sqlite")
        guard FileManager.default.fileExists(atPath: source.path) else { throw Error.noDatabase }
        root = folder

        let copy = FileManager.default.temporaryDirectory.appending(path: "nmw-applenotes-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: copy) }
        for suffix in ["", "-wal", "-shm"] {
            let file = folder.appending(path: "NoteStore.sqlite\(suffix)")
            if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.copyItem(at: file, to: copy.appending(path: "NoteStore.sqlite\(suffix)"))
            }
        }

        do {
            let queue = try DatabaseQueue(path: copy.appending(path: "NoteStore.sqlite").path)
            let read = try queue.read { db in try Self.read(db) }
            (accounts, folders, notes, attachments, media) = read
            try queue.close()
        } catch let error as Error {
            throw error
        } catch {
            throw Error.unreadable(error.localizedDescription)
        }
    }

    // MARK: Reading

    private static func read(_ db: Database) throws -> ([Account], [Folder], [Note], [String: Attachment], [Int64: Media]) {
        var entities: [String: Int64] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT Z_ENT, Z_NAME FROM Z_PRIMARYKEY") {
            entities[row["Z_NAME"]] = row["Z_ENT"]
        }
        let columns = Set(try db.columns(in: "ZICCLOUDSYNCINGOBJECT").map(\.name))
        /// The first of `names` the table has, else NULL.
        func column(_ names: String...) -> String { names.first(where: columns.contains) ?? "NULL" }
        func entity(_ name: String) -> Int64 { entities[name] ?? -1 }

        let accounts = try Row.fetchAll(db, sql: """
            SELECT Z_PK, \(column("ZIDENTIFIER")) AS identifier, \(column("ZNAME")) AS name
            FROM ZICCLOUDSYNCINGOBJECT WHERE Z_ENT = ?
            """, arguments: [entity("ICAccount")]).map {
            Account(id: $0["Z_PK"], identifier: $0["identifier"] ?? "", name: $0["name"] ?? "Notes")
        }

        let folders = try Row.fetchAll(db, sql: """
            SELECT Z_PK, \(column("ZIDENTIFIER")) AS identifier, \(column("ZTITLE2")) AS name,
                   \(column("ZPARENT")) AS parent, \(column("ZOWNER")) AS account,
                   \(column("ZFOLDERTYPE")) AS type, \(column("ZMARKEDFORDELETION")) AS deleted
            FROM ZICCLOUDSYNCINGOBJECT WHERE Z_ENT = ?
            """, arguments: [entity("ICFolder")]).compactMap { row -> Folder? in
            if (row["deleted"] as Int?) == 1 { return nil }
            // 0: a regular folder; 1: Recently Deleted; 3: smart folder.
            let type: Int = row["type"] ?? 0
            return Folder(id: row["Z_PK"], identifier: row["identifier"] ?? "", name: row["name"] ?? "Notes",
                          parentID: row["parent"], accountID: row["account"], isSpecial: type != 0)
        }

        let notes = try Row.fetchAll(db, sql: """
            SELECT n.Z_PK, \(column("ZIDENTIFIER")) AS identifier, \(column("ZTITLE1")) AS title,
                   \(column("ZFOLDER")) AS folder,
                   \(column("ZCREATIONDATE3", "ZCREATIONDATE1", "ZCREATIONDATE")) AS created,
                   \(column("ZMODIFICATIONDATE1", "ZMODIFICATIONDATE")) AS modified,
                   \(column("ZISPINNED")) AS pinned, \(column("ZISPASSWORDPROTECTED")) AS locked,
                   \(column("ZMARKEDFORDELETION")) AS deleted, d.ZDATA AS data
            FROM ZICCLOUDSYNCINGOBJECT n LEFT JOIN ZICNOTEDATA d ON d.ZNOTE = n.Z_PK
            WHERE n.Z_ENT = ?
            """, arguments: [entity("ICNote")]).map { row in
            Note(id: row["Z_PK"], identifier: row["identifier"] ?? "", title: row["title"] ?? "",
                 folderID: row["folder"],
                 created: (row["created"] as Double?).map(Date.init(timeIntervalSinceReferenceDate:)),
                 modified: (row["modified"] as Double?).map(Date.init(timeIntervalSinceReferenceDate:)),
                 pinned: (row["pinned"] as Int?) == 1, locked: (row["locked"] as Int?) == 1,
                 deleted: (row["deleted"] as Int?) == 1, data: row["data"])
        }

        var attachments: [String: Attachment] = [:]
        for row in try Row.fetchAll(db, sql: """
            SELECT Z_PK, \(column("ZIDENTIFIER")) AS identifier, \(column("ZTYPEUTI")) AS uti,
                   \(column("ZTITLE")) AS title, \(column("ZURLSTRING")) AS url, \(column("ZALTTEXT")) AS alt,
                   \(column("ZTOKENCONTENTIDENTIFIER")) AS token, \(column("ZMEDIA")) AS media,
                   \(column("ZPARENTATTACHMENT")) AS parent, \(column("ZMERGEABLEDATA1", "ZMERGEABLEDATA")) AS mergeable
            FROM ZICCLOUDSYNCINGOBJECT WHERE Z_ENT IN (?, ?)
            """, arguments: [entity("ICAttachment"), entity("ICInlineAttachment")]) {
            guard let identifier: String = row["identifier"] else { continue }
            attachments[identifier] = Attachment(
                id: row["Z_PK"], identifier: identifier, typeUTI: row["uti"] ?? "", title: row["title"],
                url: row["url"], altText: row["alt"], token: row["token"], mediaID: row["media"],
                parentID: row["parent"], mergeableData: row["mergeable"])
        }

        var media: [Int64: Media] = [:]
        for row in try Row.fetchAll(db, sql: """
            SELECT Z_PK, \(column("ZIDENTIFIER")) AS identifier, \(column("ZFILENAME")) AS fileName
            FROM ZICCLOUDSYNCINGOBJECT WHERE Z_ENT = ?
            """, arguments: [entity("ICMedia")]) {
            let id: Int64 = row["Z_PK"]
            media[id] = Media(id: id, identifier: row["identifier"] ?? "", fileName: row["fileName"])
        }
        return (accounts, folders, notes, attachments, media)
    }

    // MARK: Files

    /// The file behind a media row: `Accounts/<account>/Media/<media id>/…/<file name>`.
    public func file(for media: Media) -> URL? {
        for account in accountFolders() {
            let folder = account.appending(path: "Media/\(media.identifier)", directoryHint: .isDirectory)
            if let found = firstFile(in: folder, named: media.fileName) { return found }
        }
        return nil
    }

    /// The rendered image Notes keeps for drawings, scans and galleries.
    public func fallbackImage(for attachment: Attachment) -> URL? {
        for account in accountFolders() {
            let folder = account.appending(path: "FallbackImages", directoryHint: .isDirectory)
            let direct = ["png", "jpg", "jpeg"].map { folder.appending(path: "\(attachment.identifier).\($0)") }
            if let hit = direct.first(where: { FileManager.default.fileExists(atPath: $0.path) }) { return hit }
            let sub = folder.appending(path: attachment.identifier, directoryHint: .isDirectory)
            if let found = firstFile(in: sub, named: nil) { return found }
        }
        return nil
    }

    private func accountFolders() -> [URL] {
        let accounts = root.appending(path: "Accounts", directoryHint: .isDirectory)
        let listed = (try? FileManager.default.contentsOfDirectory(at: accounts, includingPropertiesForKeys: nil)) ?? []
        // The root itself holds Media for local "On My Mac" notes on older systems.
        return listed + [root]
    }

    /// The file called `name` under `folder` (any depth), else the first file there.
    private func firstFile(in folder: URL, named name: String?) -> URL? {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) else { return nil }
        var first: URL?
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                  !url.lastPathComponent.hasPrefix(".") else { continue }
            if let name, url.lastPathComponent == name { return url }
            if first == nil { first = url }
        }
        return first
    }
}
