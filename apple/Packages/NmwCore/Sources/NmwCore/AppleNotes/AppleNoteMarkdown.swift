//
//  AppleNoteMarkdown.swift
//  NmwCore
//
//  An Apple Notes body as Markdown. Each line of the note is a paragraph
//  with one paragraph style (title, heading, list item, checklist item,
//  monospaced, quote); runs inside it add bold, italic, strikethrough and
//  links. Attachments sit in the text as U+FFFC and are replaced by what
//  the caller's resolver returns (an image or file link, a table, …).
//

import Foundation

enum AppleNoteMarkdown {
    /// Markdown for an attachment, or nil to drop it.
    typealias AttachmentResolver = (AppleNoteBody.Attachment) -> String?

    static func convert(_ body: AppleNoteBody, attachment resolve: AttachmentResolver = { _ in nil }) -> String {
        let lines = paragraphs(of: body)
        var out: [String] = []
        var previous: Kind?
        var inCode = false

        for line in lines {
            let kind = Kind(line.paragraph)
            if inCode, kind != .code { out.append("```"); inCode = false }
            let content = inline(line.pieces, resolve: resolve)
            let blank = content.trimmingCharacters(in: .whitespaces).isEmpty

            switch kind {
            case .code:
                if !inCode {
                    if !out.isEmpty, out.last != "" { out.append("") }
                    out.append("```")
                    inCode = true
                }
                // Code keeps its text as is: no escaping, no styling.
                out.append(line.pieces.map(\.text).joined().replacingOccurrences(of: "\u{FFFC}", with: ""))
            case .list:
                if blank { if out.last != "" { out.append("") }; previous = nil; continue }
                if previous != .list, !out.isEmpty, out.last != "" { out.append("") }
                out.append(quotePrefix(line.paragraph) + listPrefix(line.paragraph) + content)
            case .heading, .text:
                if blank {
                    if !out.isEmpty, out.last != "" { out.append("") }
                    previous = nil
                    continue
                }
                if !out.isEmpty, out.last != "" { out.append("") }
                let prefix = headingPrefix(line.paragraph.style)
                let text = prefix.isEmpty ? escapeLineStart(content) : content
                out.append(quotePrefix(line.paragraph) + prefix + text)
            }
            previous = kind
        }
        if inCode { out.append("```") }
        while out.last == "" { out.removeLast() }
        return out.joined(separator: "\n") + "\n"
    }

    // MARK: Paragraphs

    struct Piece {
        var text: String
        var run: AppleNoteBody.Run
    }

    struct Line {
        var paragraph: AppleNoteBody.Paragraph
        var pieces: [Piece]
    }

    private enum Kind: Equatable {
        case text, heading, list, code

        init(_ paragraph: AppleNoteBody.Paragraph) {
            switch paragraph.style {
            case .title, .heading, .subheading: self = .heading
            case .monospaced: self = .code
            case .bullet, .dashed, .numbered, .checklist: self = .list
            default: self = .text
            }
        }
    }

    /// Splits the text at newlines; a line takes the paragraph style of its
    /// newline (the last character's run), as Notes stores it.
    static func paragraphs(of body: AppleNoteBody) -> [Line] {
        let units = Array(body.text.utf16)
        // Runs that don't cover the whole text: the rest is plain.
        var runs = body.runs.filter { $0.length > 0 }
        let covered = runs.reduce(0) { $0 + $1.length }
        if covered < units.count { runs.append(AppleNoteBody.Run(length: units.count - covered)) }

        var lines: [Line] = []
        var current: [Piece] = []
        var position = 0
        for run in runs {
            let end = min(position + run.length, units.count)
            var start = position
            var i = position
            while i < end {
                if units[i] == 0x0A {
                    if i > start { current.append(Piece(text: string(units[start..<i]), run: run)) }
                    lines.append(Line(paragraph: run.paragraph, pieces: current))
                    current = []
                    start = i + 1
                }
                i += 1
            }
            if end > start { current.append(Piece(text: string(units[start..<end]), run: run)) }
            position = end
            if position >= units.count { break }
        }
        if !current.isEmpty {
            lines.append(Line(paragraph: current.last?.run.paragraph ?? AppleNoteBody.Paragraph(), pieces: current))
        }
        return lines
    }

    private static func string(_ units: ArraySlice<UInt16>) -> String {
        String(decoding: units, as: UTF16.self)
    }

    // MARK: Inline

    private static func inline(_ pieces: [Piece], resolve: AttachmentResolver) -> String {
        var out = ""
        // Neighbouring pieces with the same styling are merged first, so a
        // bold word split over two runs gets one pair of markers.
        var merged: [Piece] = []
        for piece in pieces {
            if piece.run.attachment == nil, let last = merged.last, last.run.attachment == nil, sameStyle(last.run, piece.run) {
                merged[merged.count - 1].text += piece.text
            } else {
                merged.append(piece)
            }
        }
        for piece in merged {
            if let attachment = piece.run.attachment {
                let rest = piece.text.replacingOccurrences(of: "\u{FFFC}", with: "")
                out += resolve(attachment) ?? ""
                out += escape(rest)
                continue
            }
            out += styled(piece.text.replacingOccurrences(of: "\u{FFFC}", with: ""), piece.run)
        }
        return out
    }

    private static func sameStyle(_ a: AppleNoteBody.Run, _ b: AppleNoteBody.Run) -> Bool {
        a.bold == b.bold && a.italic == b.italic && a.strikethrough == b.strikethrough && a.link == b.link
    }

    /// Markers go around the text, not its surrounding spaces (`** x **` isn't bold).
    private static func styled(_ text: String, _ run: AppleNoteBody.Run) -> String {
        let leading = String(text.prefix { $0 == " " || $0 == "\t" })
        let trailing = String(text.dropFirst(leading.count).reversed().prefix { $0 == " " || $0 == "\t" })
        let core = String(text.dropFirst(leading.count).dropLast(trailing.count))
        guard !core.isEmpty else { return text }
        var s = escape(core)
        if run.strikethrough { s = "~~\(s)~~" }
        if run.italic { s = "*\(s)*" }
        if run.bold { s = "**\(s)**" }
        if let link = run.link, !link.isEmpty {
            s = "[\(s)](\(link.replacingOccurrences(of: " ", with: "%20").replacingOccurrences(of: ")", with: "%29")))"
        }
        return leading + s + String(trailing.reversed())
    }

    /// Escapes what Markdown would read as formatting.
    static func escape(_ text: String) -> String {
        var out = ""
        for ch in text {
            if "\\`*_[]<".contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    /// A plain line that would start a heading, list, quote or rule gets a backslash.
    private static func escapeLineStart(_ line: String) -> String {
        let trimmed = line.drop { $0 == " " }
        guard let first = trimmed.first else { return line }
        if first == "#" || first == ">" { return "\\" + line }
        if "-+".contains(first), trimmed.dropFirst().first == " " || trimmed.count == 1 { return "\\" + line }
        if first.isNumber, let dot = trimmed.firstIndex(where: { !$0.isNumber }), ".)".contains(trimmed[dot]),
           trimmed[trimmed.index(after: dot)...].first == " " {
            return line.replacingCharacters(in: line.range(of: String(trimmed[dot]))!, with: "\\" + String(trimmed[dot]))
        }
        return line
    }

    // MARK: Prefixes

    private static func headingPrefix(_ style: AppleNoteBody.Style) -> String {
        switch style {
        case .title: "# "
        case .heading: "## "
        case .subheading: "### "
        default: ""
        }
    }

    private static func listPrefix(_ p: AppleNoteBody.Paragraph) -> String {
        let indent = String(repeating: "    ", count: max(0, p.indent))
        switch p.style {
        case .numbered: return indent + "1. "
        case .checklist: return indent + (p.checked == true ? "- [x] " : "- [ ] ")
        default: return indent + "- "
        }
    }

    private static func quotePrefix(_ p: AppleNoteBody.Paragraph) -> String { p.quote ? "> " : "" }
}
