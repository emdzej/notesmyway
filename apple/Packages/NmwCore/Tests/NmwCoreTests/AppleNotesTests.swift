//
//  AppleNotesTests.swift
//  NmwCoreTests
//
//  The Apple Notes importer on synthetic data: note bodies encoded like
//  Notes encodes them (gzipped protobuf), and a NoteStore.sqlite with the
//  tables and columns the importer reads.
//

import Foundation
import GRDB
import Testing
@testable import NmwCore

// MARK: - Encoding notes like Apple Notes

private struct ProtoWriter {
    var data = Data()

    mutating func varint(_ field: Int, _ value: Int) {
        key(field, 0)
        put(UInt64(value))
    }

    mutating func bytes(_ field: Int, _ value: Data) {
        key(field, 2)
        put(UInt64(value.count))
        data.append(value)
    }

    mutating func string(_ field: Int, _ value: String) { bytes(field, Data(value.utf8)) }
    mutating func message(_ field: Int, _ build: (inout ProtoWriter) -> Void) {
        var inner = ProtoWriter()
        build(&inner)
        bytes(field, inner.data)
    }

    private mutating func key(_ field: Int, _ type: Int) { put(UInt64(field << 3 | type)) }
    private mutating func put(_ value: UInt64) {
        var v = value
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            data.append(byte)
        } while v != 0
    }
}

/// One attribute run, as the test describes it.
private struct R {
    var text: String
    var style: Int? = nil
    var indent = 0
    var checked: Bool? = nil
    var quote = false
    var weight = 0
    var strike = false
    var link: String? = nil
    var attachment: (String, String)? = nil
}

private func noteData(_ runs: [R], gzip: Bool = true) -> Data {
    var root = ProtoWriter()
    root.message(2) { document in
        document.varint(2, 0)
        document.message(3) { note in
            note.string(2, runs.map(\.text).joined())
            for r in runs {
                note.message(5) { run in
                    run.varint(1, r.text.utf16.count)
                    if r.style != nil || r.indent > 0 || r.checked != nil || r.quote {
                        run.message(2) { p in
                            if let style = r.style { p.varint(1, style) }
                            if r.indent > 0 { p.varint(4, r.indent) }
                            if let checked = r.checked {
                                p.message(5) { c in
                                    c.bytes(1, Data([1, 2, 3]))
                                    c.varint(2, checked ? 1 : 0)
                                }
                            }
                            if r.quote { p.varint(8, 1) }
                        }
                    }
                    if r.weight != 0 { run.varint(5, r.weight) }
                    if r.strike { run.varint(7, 1) }
                    if let link = r.link { run.string(9, link) }
                    if let (id, uti) = r.attachment {
                        run.message(12) { a in
                            a.string(1, id)
                            a.string(2, uti)
                        }
                    }
                }
            }
        }
    }
    return gzip ? gzipped(root.data) : root.data
}

/// A gzip member around raw deflate (CRC left zero: the reader doesn't check it).
private func gzipped(_ data: Data) -> Data {
    let deflated = try! (data as NSData).compressed(using: .zlib) as Data
    var out = Data([0x1F, 0x8B, 8, 0, 0, 0, 0, 0, 0, 3])
    out.append(deflated)
    out.append(contentsOf: [0, 0, 0, 0])
    let size = UInt32(truncatingIfNeeded: data.count)
    out.append(contentsOf: [UInt8(size & 0xFF), UInt8(size >> 8 & 0xFF), UInt8(size >> 16 & 0xFF), UInt8(size >> 24)])
    return out
}

private func markdown(_ runs: [R]) throws -> String {
    AppleNoteMarkdown.convert(try AppleNoteBody(data: noteData(runs)))
}

/// A `com.apple.notes.table` document: `rows` and `columns` are UUID
/// indices in display order; `cells[row][column]` are the cell runs.
private func tableData(rowsInDisplayOrder rows: [Int], columns: [Int], cells: [Int: [Int: [R]]]) -> Data {
    let uuids = (0..<4).map { i in Data((0..<16).map { UInt8($0 + i * 16) }) }   // rowA, rowB, colA, colB
    var entries: [ProtoWriter] = []
    func add(_ build: (inout ProtoWriter) -> Void) -> Int {
        var w = ProtoWriter(); build(&w); entries.append(w); return entries.count - 1
    }
    func objectID(_ w: inout ProtoWriter, field: Int, index: Int) { w.message(field) { $0.varint(6, index) } }
    // Index 0 is the table; filled in last.
    entries.append(ProtoWriter())
    // An entry standing for each UUID: a map whose first value is the UUID index.
    let uuidRefs = (0..<4).map { u in add { e in e.message(13) { m in m.varint(1, 1); m.message(3) { me in me.varint(1, 3); me.message(2) { $0.varint(2, u) } } } } }
    func orderedSet(_ order: [Int]) -> Int {
        add { e in e.message(16) { set in set.message(1) { ordering in
            ordering.message(1) { array in for u in order { array.message(2) { a in a.varint(1, 0); a.bytes(2, uuids[u]) } } }
            ordering.message(2) { dict in for u in order { dict.message(1) { el in objectID(&el, field: 1, index: uuidRefs[u]); objectID(&el, field: 2, index: uuidRefs[u]) } } }
        } } }
    }
    let rowSet = orderedSet(rows)
    let columnSet = orderedSet(columns)
    var columnDicts: [(Int, Int)] = []
    for column in columns {
        var rowCells: [(Int, Int)] = []
        for row in rows {
            guard let runs = cells[row]?[column] else { continue }
            let note = add { e in e.message(10) { n in
                n.string(2, runs.map(\.text).joined())
                for r in runs { n.message(5) { run in run.varint(1, r.text.utf16.count); if r.weight != 0 { run.varint(5, r.weight) } } }
            } }
            rowCells.append((uuidRefs[row], note))
        }
        let dict = add { e in e.message(6) { d in for (key, value) in rowCells { d.message(1) { el in objectID(&el, field: 1, index: key); objectID(&el, field: 2, index: value) } } } }
        columnDicts.append((uuidRefs[column], dict))
    }
    let cellColumns = add { e in e.message(6) { d in for (key, value) in columnDicts { d.message(1) { el in objectID(&el, field: 1, index: key); objectID(&el, field: 2, index: value) } } } }
    var table = ProtoWriter()
    table.message(13) { m in
        m.varint(1, 0)
        for (key, target) in [(0, rowSet), (1, columnSet), (2, cellColumns)] {
            m.message(3) { me in me.varint(1, key); me.message(2) { $0.varint(6, target) } }
        }
    }
    entries[0] = table

    var root = ProtoWriter()
    root.message(2) { object in
        object.varint(2, 0)
        object.message(3) { data in
            for e in entries { data.bytes(3, e.data) }
            for key in ["crRows", "crColumns", "cellColumns", "self"] { data.string(4, key) }
            for type in ["com.apple.notes.ICTable", "com.apple.CRDT.NSUUID"] { data.string(5, type) }
            for u in uuids { data.bytes(6, u) }
        }
    }
    return gzipped(root.data)
}

private let sampleTable = tableData(rowsInDisplayOrder: [1, 0], columns: [2, 3], cells: [
    1: [2: [R(text: "Item")], 3: [R(text: "Price")]],
    0: [2: [R(text: "Tap | mixer\nchrome")], 3: [R(text: "189", weight: 1)]],
])

// MARK: - Bodies

@Suite("Apple Notes bodies")
struct AppleNoteBodyTests {

    @Test func decodesTextAndRunsFromGzip() throws {
        let body = try AppleNoteBody(data: noteData([R(text: "Title\n", style: 0), R(text: "Hello "), R(text: "world", weight: 1)]))
        #expect(body.text == "Title\nHello world")
        #expect(body.runs.count == 3)
        #expect(body.runs[0].paragraph.style == .title)
        #expect(body.runs[2].bold)
        #expect(try AppleNoteBody(data: noteData([R(text: "x")], gzip: false)).text == "x")
    }

    @Test func headingsAndInlineStyles() throws {
        let md = try markdown([
            R(text: "Groceries\n", style: 0),
            R(text: "This week\n", style: 1),
            R(text: "Buy "), R(text: "fresh", weight: 1), R(text: " and "), R(text: "cheap ", weight: 2),
            R(text: "milk", strike: true), R(text: " at "), R(text: "the shop", link: "https://example.com/a b"), R(text: "\n"),
            R(text: "Details\n", style: 2),
        ])
        #expect(md == """
        # Groceries

        ## This week

        Buy **fresh** and *cheap* ~~milk~~ at [the shop](https://example.com/a%20b)

        ### Details

        """)
    }

    @Test func listsChecklistsQuotesAndCode() throws {
        let md = try markdown([
            R(text: "Packing\n", style: 0),
            R(text: "Shoes\n", style: 103, checked: false),
            R(text: "Jacket\n", style: 103, checked: true),
            R(text: "Socks\n", style: 100, indent: 1),
            R(text: "First\n", style: 102),
            R(text: "Second\n", style: 102),
            R(text: "Be brave\n", quote: true),
            R(text: "let x = 1\n", style: 4),
            R(text: "print(x)\n", style: 4),
            R(text: "Done"),
        ])
        #expect(md == """
        # Packing

        - [ ] Shoes
        - [x] Jacket
            - Socks
        1. First
        1. Second

        > Be brave

        ```
        let x = 1
        print(x)
        ```

        Done

        """)
    }

    @Test func escapesWhatMarkdownWouldRead() throws {
        let md = try markdown([R(text: "# not a heading\n"), R(text: "1. not a list\n"), R(text: "a*b_c [x] `y`")])
        #expect(md == """
        \\# not a heading

        1\\. not a list

        a\\*b\\_c \\[x\\] \\`y\\`

        """)
    }

    @Test func attachmentsAreResolvedInPlace() throws {
        let body = try AppleNoteBody(data: noteData([R(text: "Photo\n", style: 0), R(text: "\u{FFFC}", attachment: ("A1", "public.jpeg")), R(text: "\nAfter")]))
        let md = AppleNoteMarkdown.convert(body) { $0.identifier == "A1" ? "![](img.jpg)" : nil }
        #expect(md == "# Photo\n\n![](img.jpg)\n\nAfter\n")
    }

    @Test func tablesFollowTheirRowAndColumnOrder() throws {
        let table = try AppleNoteTable(data: sampleTable)
        #expect(table.cells.count == 2)
        #expect(table.cells[0].map(\.text) == ["Item", "Price"])
        #expect(table.markdown() == """
        | Item | Price |
        | --- | --- |
        | Tap \\| mixer<br>chrome | **189** |
        """)
        #expect(throws: (any Error).self) { try AppleNoteTable(data: noteData([R(text: "not a table")])) }
    }

    @Test func emojiCountsInUTF16() throws {
        let md = try markdown([R(text: "😀 "), R(text: "bold", weight: 1), R(text: " end")])
        #expect(md == "😀 **bold** end\n")
    }
}

// MARK: - Library and import

@Suite("Apple Notes import")
struct AppleNotesImportTests {

    /// A Notes data folder: NoteStore.sqlite plus Media and FallbackImages.
    private func makeNotesFolder(in root: URL) throws -> URL {
        let folder = root.appending(path: "group.com.apple.notes", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: folder.appending(path: "NoteStore.sqlite").path)
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE Z_PRIMARYKEY (Z_ENT INTEGER, Z_NAME TEXT);
                INSERT INTO Z_PRIMARYKEY VALUES (5, 'ICAttachment'), (8, 'ICAccount'), (12, 'ICFolder'),
                    (14, 'ICInlineAttachment'), (16, 'ICMedia'), (11, 'ICNote');
                CREATE TABLE ZICCLOUDSYNCINGOBJECT (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, ZIDENTIFIER TEXT,
                    ZNAME TEXT, ZTITLE1 TEXT, ZTITLE2 TEXT, ZTITLE TEXT, ZPARENT INTEGER, ZOWNER INTEGER, ZFOLDERTYPE INTEGER,
                    ZFOLDER INTEGER, ZCREATIONDATE3 REAL, ZMODIFICATIONDATE1 REAL, ZISPINNED INTEGER,
                    ZISPASSWORDPROTECTED INTEGER, ZMARKEDFORDELETION INTEGER, ZTYPEUTI TEXT, ZMEDIA INTEGER,
                    ZURLSTRING TEXT, ZALTTEXT TEXT, ZTOKENCONTENTIDENTIFIER TEXT, ZFILENAME TEXT,
                    ZPARENTATTACHMENT INTEGER, ZMERGEABLEDATA1 BLOB);
                CREATE TABLE ZICNOTEDATA (Z_PK INTEGER PRIMARY KEY, ZNOTE INTEGER, ZDATA BLOB);
                INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZNAME) VALUES (1, 8, 'ACC-1', 'iCloud');
                INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZTITLE2, ZOWNER, ZFOLDERTYPE) VALUES
                    (2, 12, 'F-NOTES', 'Notes', 1, 0), (3, 12, 'F-TRIPS', 'Trips', 1, 0), (4, 12, 'F-TRASH', 'Recently Deleted', 1, 1);
                UPDATE ZICCLOUDSYNCINGOBJECT SET ZPARENT = 2 WHERE Z_PK = 3;
                """)
            let lisbonID = "11111111-2222-3333-4444-555555555555"
            func note(_ pk: Int64, _ id: String, _ title: String, folder: Int64, pinned: Bool = false, locked: Bool = false, _ runs: [R]) throws {
                try db.execute(sql: """
                    INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZTITLE1, ZFOLDER, ZCREATIONDATE3, ZMODIFICATIONDATE1,
                        ZISPINNED, ZISPASSWORDPROTECTED, ZMARKEDFORDELETION) VALUES (?, 11, ?, ?, ?, ?, ?, ?, ?, 0)
                    """, arguments: [pk, id, title, folder, 800_000_000.0, 815_000_000.0, pinned ? 1 : 0, locked ? 1 : 0])
                try db.execute(sql: "INSERT INTO ZICNOTEDATA (ZNOTE, ZDATA) VALUES (?, ?)", arguments: [pk, noteData(runs)])
            }
            try note(10, lisbonID, "Lisbon", folder: 3, pinned: true, [
                R(text: "Lisbon\n", style: 0),
                R(text: "\u{FFFC}", attachment: ("ATT-PHOTO", "public.jpeg")), R(text: "\n"),
                R(text: "Tram 28 "), R(text: "\u{FFFC}", attachment: ("ATT-TAG", "com.apple.notes.inlinetextattachment.hashtag")), R(text: "\n"),
                R(text: "\u{FFFC}", attachment: ("ATT-TABLE", "com.apple.notes.table")),
            ])
            try note(11, "NOTE-2", "Ideas", folder: 2, [
                R(text: "Ideas\n"),
                R(text: "See "), R(text: "\u{FFFC}", attachment: ("ATT-LINK", "com.apple.notes.inlinetextattachment.link")), R(text: "\n"),
                R(text: "\u{FFFC}", attachment: ("ATT-DRAW", "com.apple.drawing.2")), R(text: "\n"),
                R(text: "\u{FFFC}", attachment: ("ATT-URL", "public.url")), R(text: "\n"),
                R(text: "\u{FFFC}", attachment: ("ATT-BROKEN", "com.apple.notes.table")),
            ])
            try note(12, "NOTE-3", "Secret", folder: 2, locked: true, [R(text: "x")])
            try note(13, "NOTE-4", "Old", folder: 4, [R(text: "Old")])
            try note(14, "NOTE-5", "Ideas", folder: 2, [R(text: "Ideas\nsecond one")])
            try db.execute(sql: """
                INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZTYPEUTI, ZMEDIA) VALUES (20, 5, 'ATT-PHOTO', 'public.jpeg', 30);
                INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZFILENAME) VALUES (30, 16, 'MEDIA-1', 'tram.jpg');
                INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZTYPEUTI, ZALTTEXT) VALUES (21, 14, 'ATT-TAG', 'com.apple.notes.inlinetextattachment.hashtag', '#travel');
                INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZTYPEUTI) VALUES (22, 5, 'ATT-TABLE', 'com.apple.notes.table');
                INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZTYPEUTI) VALUES (26, 5, 'ATT-BROKEN', 'com.apple.notes.table');
                INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZTYPEUTI, ZALTTEXT, ZTOKENCONTENTIDENTIFIER) VALUES
                    (23, 14, 'ATT-LINK', 'com.apple.notes.inlinetextattachment.link', 'Lisbon', 'applenotes:note/11111111-2222-3333-4444-555555555555?ownerIdentifier=x');
                INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZTYPEUTI) VALUES (24, 5, 'ATT-DRAW', 'com.apple.drawing.2');
                INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZTYPEUTI, ZURLSTRING, ZTITLE) VALUES (25, 5, 'ATT-URL', 'public.url', 'https://example.com', 'Example');
                """)
            try db.execute(sql: "UPDATE ZICCLOUDSYNCINGOBJECT SET ZMERGEABLEDATA1 = ? WHERE Z_PK = 22", arguments: [sampleTable])
        }
        try queue.close()
        let media = folder.appending(path: "Accounts/ACC-1/Media/MEDIA-1/1_ABC", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        try Data([0xFF, 0xD8, 0xFF, 0xE0]).write(to: media.appending(path: "tram.jpg"))
        let fallback = folder.appending(path: "Accounts/ACC-1/FallbackImages", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: fallback.appending(path: "ATT-DRAW.png"))
        return folder
    }

    @Test func readsTheLibrary() throws {
        let temp = try TempFolder()
        defer { temp.delete() }
        let library = try AppleNotesLibrary(folder: try makeNotesFolder(in: temp.url))
        #expect(library.accounts.map(\.name) == ["iCloud"])
        #expect(library.folders.count == 3)
        #expect(library.folders.first { $0.name == "Recently Deleted" }?.isSpecial == true)
        #expect(library.notes.count == 5)
        let lisbon = try #require(library.notes.first { $0.title == "Lisbon" })
        #expect(lisbon.pinned)
        #expect(lisbon.created == Date(timeIntervalSinceReferenceDate: 800_000_000))
        #expect(library.attachments["ATT-TAG"]?.altText == "#travel")
        #expect(throws: AppleNotesLibrary.Error.noDatabase) { try AppleNotesLibrary(folder: temp.url) }
    }

    @Test func importsIntoANotebook() throws {
        let temp = try TempFolder()
        defer { temp.delete() }
        let library = try AppleNotesLibrary(folder: try makeNotesFolder(in: temp.url))
        let notebook = temp.url.appending(path: "Notebook", directoryHint: .isDirectory)
        let destination = notebook.appending(path: "Apple Notes", directoryHint: .isDirectory)
        let importer = AppleNotesImporter(library: library, notebookRoot: notebook)
        #expect(importer.importableCount == 3)

        var progress: [Int] = []
        let report = importer.run(into: destination) { done, _ in progress.append(done) }
        #expect(report.imported == 3)
        #expect(report.locked == 1)
        #expect(report.tables == 1)
        #expect(report.missingAttachments == 0)
        #expect(report.failures.isEmpty)
        #expect(progress == [1, 2, 3])

        let lisbonURL = destination.appending(path: "Notes/Trips/Lisbon.md")
        let lisbon = try String(contentsOf: lisbonURL, encoding: .utf8)
        #expect(lisbon == """
        ---
        created: 2026-05-09T06:13:20Z
        pinned: true
        ---
        # Lisbon

        ![](.attachments/tram.jpg)

        Tram 28 #travel

        | Item | Price |
        | --- | --- |
        | Tap \\| mixer<br>chrome | **189** |

        """)
        #expect(FileManager.default.fileExists(atPath: destination.appending(path: "Notes/Trips/.attachments/tram.jpg").path))
        let modified = try FileManager.default.attributesOfItem(atPath: lisbonURL.path)[.modificationDate] as? Date
        #expect(modified == Date(timeIntervalSinceReferenceDate: 815_000_000))

        let ideas = try String(contentsOf: destination.appending(path: "Notes/Ideas.md"), encoding: .utf8)
        #expect(ideas.contains("# Ideas\n"))
        #expect(ideas.contains("See [Lisbon](Trips/Lisbon.md)"))
        #expect(ideas.contains("![](.attachments/ATT-DRAW.png)"))
        #expect(ideas.contains("[Example](https://example.com)"))
        #expect(ideas.contains("*(A table from Apple Notes that couldn’t be converted.)*"))
        // Same title twice: the second gets a number.
        let second = try String(contentsOf: destination.appending(path: "Notes/Ideas 2.md"), encoding: .utf8)
        #expect(second.hasPrefix("---\ncreated: 2026-05-09T06:13:20Z\n---\n# Ideas\n\nsecond one\n"))
        // Locked and deleted notes stay behind.
        #expect(!FileManager.default.fileExists(atPath: destination.appending(path: "Notes/Secret.md").path))
        #expect(!FileManager.default.fileExists(atPath: destination.appending(path: "Recently Deleted").path))

        // The imported notes index like any others.
        let meta = NoteMetadata(markdown: lisbon, fileName: "Lisbon")
        #expect(meta.title == "Lisbon")
        #expect(meta.pinned)
        #expect(meta.tags == ["travel"])
    }

    @Test func noteIdentifiersComeOutOfLinkTokens() {
        #expect(AppleNotesImporter.noteIdentifier(in: "applenotes:note/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee?ownerIdentifier=x")
                == "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        #expect(AppleNotesImporter.noteIdentifier(in: "nothing here") == nil)
        #expect(AppleNotesImporter.fileName("a/b: c", fallback: "x") == "a-b- c")
        #expect(AppleNotesImporter.fileName("  ", fallback: "Untitled") == "Untitled")
    }
}
