//
//  AppleNoteBody.swift
//  NmwCore
//
//  A note body from Apple Notes' database (`ZICNOTEDATA.ZDATA`): gzipped
//  protobuf holding the plain text and attribute runs over it (paragraph
//  styles, bold / italic, links, attachments). Field numbers follow the
//  community-documented `notestore.proto`:
//
//    NoteStoreProto { Document document = 2 }
//    Document       { Note note = 3 }
//    Note           { string note_text = 2; repeated AttributeRun attribute_run = 5 }
//    AttributeRun   { length = 1; ParagraphStyle = 2; Font = 3; font_weight = 5;
//                     underlined = 6; strikethrough = 7; superscript = 8;
//                     link = 9; color = 10; AttachmentInfo = 12 }
//    ParagraphStyle { style_type = 1; alignment = 2; indent_amount = 4;
//                     Checklist checklist = 5 { uuid = 1; done = 2 }; block_quote = 8 }
//    AttachmentInfo { attachment_identifier = 1; type_uti = 2 }
//
//  Run lengths count UTF-16 code units.
//

import Foundation

struct AppleNoteBody: Equatable {
    var text: String
    var runs: [Run]

    struct Run: Equatable {
        var length: Int
        var paragraph = Paragraph()
        var bold = false
        var italic = false
        var underlined = false
        var strikethrough = false
        var link: String?
        var attachment: Attachment?
    }

    struct Paragraph: Equatable {
        var style: Style = .body
        var indent = 0
        /// Set for checklist items.
        var checked: Bool?
        var quote = false
    }

    enum Style: Equatable {
        case body, title, heading, subheading, monospaced, bullet, dashed, numbered, checklist
        case other(Int)

        init(_ raw: Int) {
            switch raw {
            case -1: self = .body
            case 0: self = .title
            case 1: self = .heading
            case 2: self = .subheading
            case 4: self = .monospaced
            case 100: self = .bullet
            case 101: self = .dashed
            case 102: self = .numbered
            case 103: self = .checklist
            default: self = .other(raw)
            }
        }

        var isList: Bool { [.bullet, .dashed, .numbered, .checklist].contains(self) }
    }

    struct Attachment: Equatable {
        var identifier: String
        var typeUTI: String
    }

    /// Decodes a `ZDATA` blob (gzipped or not).
    init(data: Data) throws {
        let raw = Gzip.isGzip(data) ? try Gzip.decompress(data) : data
        let root = try ProtoReader.fields(of: raw)
        guard let note = root.first(2)?.message.first(3)?.message else { throw ProtoReader.Malformed() }
        self.init(note: note)
    }

    /// From a `Note` message (a note body, or a table cell).
    init(note: [ProtoField]) {
        text = note.first(2)?.string ?? ""
        runs = note.all(5).map { Self.run($0.message) }
    }

    init(text: String, runs: [Run]) {
        self.text = text
        self.runs = runs
    }

    private static func run(_ fields: [ProtoField]) -> Run {
        var run = Run(length: fields.first(1)?.int ?? 0)
        if let style = fields.first(2)?.message {
            run.paragraph.style = style.first(1).map { Style($0.int) } ?? .body
            run.paragraph.indent = style.first(4)?.int ?? 0
            if let checklist = style.first(5)?.message {
                run.paragraph.checked = (checklist.first(2)?.int ?? 0) != 0
            }
            run.paragraph.quote = (style.first(8)?.int ?? 0) != 0
        }
        // font_weight: 1 bold, 2 italic, 3 bold italic.
        let weight = fields.first(5)?.int ?? 0
        run.bold = weight == 1 || weight == 3
        run.italic = weight == 2 || weight == 3
        run.underlined = (fields.first(6)?.int ?? 0) != 0
        run.strikethrough = (fields.first(7)?.int ?? 0) != 0
        run.link = fields.first(9)?.string
        if let info = fields.first(12)?.message, let id = info.first(1)?.string {
            run.attachment = Attachment(identifier: id, typeUTI: info.first(2)?.string ?? "")
        }
        return run
    }
}
