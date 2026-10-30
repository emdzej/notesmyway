//
//  AppleNoteTable.swift
//  NmwCore
//
//  An Apple Notes table (`com.apple.notes.table`). Its data
//  (`ZMERGEABLEDATA1`) is a gzipped CRDT document: a flat list of objects
//  that refer to each other by index, plus tables of key names, type names
//  and UUIDs. Field numbers follow the community-documented
//  `MergableDataProto`:
//
//    MergableDataProto     { MergableDataObject object = 2 }
//    MergableDataObject    { version = 2; Data data = 3 }
//    Data                  { repeated Entry entry = 3; repeated string key_item = 4;
//                            repeated string type_item = 5; repeated bytes uuid_item = 6 }
//    Entry                 { RegisterLatest = 1; List = 5; Dictionary dictionary = 6;
//                            Note note = 10; Map custom_map = 13; OrderedSet ordered_set = 16 }
//    Map                   { type = 1; repeated MapEntry entry = 3 }    MapEntry { key = 1; ObjectID value = 2 }
//    Dictionary            { repeated Element element = 1 }            Element  { ObjectID key = 1; ObjectID value = 2 }
//    ObjectID              { unsigned_integer_value = 2; string_value = 4; object_index = 6 }
//    OrderedSet            { Ordering ordering = 1; Dictionary elements = 2 }
//    Ordering              { Array array = 1; Dictionary contents = 2 }
//    Array                 { Note contents = 1; repeated Attachment attachment = 2 }   Attachment { index = 1; bytes uuid = 2 }
//
//  The table is the entry whose map type is `com.apple.notes.ICTable`. Its
//  `crRows` and `crColumns` are ordered sets of UUIDs (their order is the
//  grid's), and `cellColumns` maps column → (row → cell), each cell a Note.
//

import Foundation

struct AppleNoteTable: Equatable {
    /// Rows of cells, top to bottom, left to right.
    var cells: [[AppleNoteBody]]

    init(cells: [[AppleNoteBody]]) {
        self.cells = cells
    }

    /// Decodes `ZMERGEABLEDATA1` (gzipped or not).
    init(data: Data) throws {
        let raw = Gzip.isGzip(data) ? try Gzip.decompress(data) : data
        guard let document = try ProtoReader.fields(of: raw).first(2)?.message.first(3)?.message else {
            throw ProtoReader.Malformed()
        }
        let entries = document.all(3).map(\.message)
        let keys = document.all(4).map(\.string)
        let types = document.all(5).map(\.string)
        let uuids = document.all(6).map(\.bytes)

        guard let table = entries.first(where: { entry in
            guard let map = entry.first(13)?.message, let type = map.first(1)?.int, types.indices.contains(type) else { return false }
            return types[type] == "com.apple.notes.ICTable"
        })?.first(13)?.message else { throw ProtoReader.Malformed() }

        func entry(_ id: [ProtoField]?) -> [ProtoField]? {
            guard let index = id?.first(6)?.int, entries.indices.contains(index) else { return nil }
            return entries[index]
        }
        /// The UUID index an entry stands for (a map whose first value is it).
        func uuidIndex(_ entry: [ProtoField]?) -> Int? {
            entry?.first(13)?.message.first(3)?.message.first(2)?.message.first(2)?.int
        }
        /// UUID index → position, from an ordered set (`crRows` / `crColumns`).
        func order(_ set: [ProtoField]?) -> [Int: Int] {
            guard let ordering = set?.first(16)?.message.first(1)?.message else { return [:] }
            var positions: [Int: Int] = [:]
            for (position, attachment) in (ordering.first(1)?.message.all(2) ?? []).enumerated() {
                let uuid = attachment.message.first(2)?.bytes ?? Data()
                if let index = uuids.firstIndex(of: uuid) { positions[index] = position }
            }
            // Contents map element UUIDs to the ordering's UUIDs.
            for element in ordering.first(2)?.message.all(1) ?? [] {
                let pair = element.message
                if let key = uuidIndex(entry(pair.first(1)?.message)),
                   let value = uuidIndex(entry(pair.first(2)?.message)),
                   let position = positions[key] {
                    positions[value] = position
                }
            }
            return positions
        }

        var rows: [Int: Int] = [:], columns: [Int: Int] = [:]
        var cellColumns: [ProtoField]?
        for item in table.all(3) {
            let pair = item.message
            guard let key = pair.first(1)?.int, keys.indices.contains(key) else { continue }
            let value = entry(pair.first(2)?.message)
            switch keys[key] {
            case "crRows": rows = order(value)
            case "crColumns": columns = order(value)
            case "cellColumns": cellColumns = value
            default: break
            }
        }

        let rowCount = (rows.values.max() ?? -1) + 1
        let columnCount = (columns.values.max() ?? -1) + 1
        var grid = Array(repeating: Array(repeating: AppleNoteBody(text: "", runs: []), count: columnCount), count: rowCount)
        for column in cellColumns?.first(6)?.message.all(1) ?? [] {
            let columnPair = column.message
            guard let c = uuidIndex(entry(columnPair.first(1)?.message)).flatMap({ columns[$0] }),
                  let rowsOfColumn = entry(columnPair.first(2)?.message)?.first(6)?.message else { continue }
            for cell in rowsOfColumn.all(1) {
                let cellPair = cell.message
                guard let r = uuidIndex(entry(cellPair.first(1)?.message)).flatMap({ rows[$0] }),
                      let note = entry(cellPair.first(2)?.message)?.first(10)?.message,
                      grid.indices.contains(r), grid[r].indices.contains(c) else { continue }
                grid[r][c] = AppleNoteBody(note: note)
            }
        }
        cells = grid
    }

    /// A GFM table; the first row is the header (Notes' tables have none).
    func markdown() -> String {
        guard let width = cells.map(\.count).max(), width > 0, !cells.isEmpty else { return "" }
        func cell(_ body: AppleNoteBody) -> String {
            let md = AppleNoteMarkdown.convert(body).trimmingCharacters(in: .whitespacesAndNewlines)
            return md.replacingOccurrences(of: "|", with: "\\|")
                .replacingOccurrences(of: "\n\n", with: "<br>").replacingOccurrences(of: "\n", with: "<br>")
        }
        func row(_ bodies: [AppleNoteBody]) -> String {
            let texts = (0..<width).map { $0 < bodies.count ? cell(bodies[$0]) : "" }
            return "| " + texts.joined(separator: " | ") + " |"
        }
        var lines = [row(cells[0]), "|" + String(repeating: " --- |", count: width)]
        lines += cells.dropFirst().map(row)
        return lines.joined(separator: "\n")
    }
}
