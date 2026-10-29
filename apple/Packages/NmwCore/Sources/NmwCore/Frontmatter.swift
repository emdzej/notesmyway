//
//  Frontmatter.swift
//  NmwCore
//
//  The optional `---` YAML block at the top of a note. nmw reads a small
//  subset (scalars, `[a, b]` and `- a` lists) and edits single keys in
//  place, so everything else in the block, and the rest of the file, stays
//  byte-for-byte as written.
//

import Foundation

public struct Frontmatter: Equatable, Sendable {

    public enum Value: Equatable, Sendable {
        case scalar(String)
        case list([String])
    }

    public struct Field: Equatable, Sendable {
        public let key: String
        public let value: Value
    }

    public let fields: [Field]
    /// The whole block, delimiters and trailing newline included.
    public let range: Range<String.Index>

    public subscript(key: String) -> Value? { fields.last { $0.key == key }?.value }

    public var tags: [String] {
        switch self["tags"] ?? self["tag"] {
        case .list(let items)?: return items.map(Self.tagName).filter { !$0.isEmpty }
        case .scalar(let s)?:
            // `tags: a, b` and `tags: a b` both occur in the wild.
            return s.split(whereSeparator: { $0 == "," || $0 == " " }).map { Self.tagName(String($0)) }.filter { !$0.isEmpty }
        case nil: return []
        }
    }

    public var pinned: Bool {
        if case .scalar(let s)? = self["pinned"] { return ["true", "yes", "on"].contains(s.lowercased()) }
        return false
    }

    public var created: Date? {
        guard case .scalar(let s)? = self["created"] else { return nil }
        return Self.parseDate(s)
    }

    // MARK: Parsing

    /// The frontmatter of `text`, or nil when it doesn't start with a `---` block.
    public static func parse(_ text: String) -> Frontmatter? {
        var start = text.startIndex
        if text.hasPrefix("\u{FEFF}") { start = text.index(after: start) }
        guard let first = line(in: text, from: start), first.content.trimmingTrailingSpace == "---" else { return nil }

        var fields: [Field] = []
        var pendingListKey: String?
        var pendingList: [String] = []
        func flushList() {
            if let key = pendingListKey { fields.append(Field(key: key, value: .list(pendingList))) }
            pendingListKey = nil
            pendingList = []
        }

        var cursor = first.next
        while let l = line(in: text, from: cursor) {
            let content = l.content.trimmingTrailingSpace
            if content == "---" || content == "..." {
                flushList()
                return Frontmatter(fields: fields, range: text.startIndex..<l.next)
            }
            let trimmed = content.drop(while: { $0 == " " || $0 == "\t" })
            if pendingListKey != nil, trimmed.hasPrefix("- ") || trimmed == "-" {
                pendingList.append(unquote(String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces)))
            } else if !content.hasPrefix(" "), !content.hasPrefix("\t"), !content.hasPrefix("#"),
                      let colon = content.firstIndex(of: ":") {
                flushList()
                let key = content[..<colon].trimmingCharacters(in: .whitespaces)
                let rest = content[content.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if rest.isEmpty {
                    pendingListKey = key
                } else if rest.hasPrefix("["), rest.hasSuffix("]") {
                    let items = rest.dropFirst().dropLast().split(separator: ",")
                        .map { unquote($0.trimmingCharacters(in: .whitespaces)) }.filter { !$0.isEmpty }
                    fields.append(Field(key: key, value: .list(items)))
                } else {
                    fields.append(Field(key: key, value: .scalar(unquote(rest))))
                }
            }
            // Anything else (nested maps, block scalars) is kept but not read.
            cursor = l.next
        }
        return nil   // never closed: not frontmatter
    }

    /// Text after the frontmatter (the whole text when there is none).
    public static func body(of text: String) -> Substring {
        guard let fm = parse(text) else { return text[...] }
        return text[fm.range.upperBound...]
    }

    // MARK: Editing

    /// `text` with `key` set to `value` (or removed when nil). Only that
    /// key's lines change; a block is added at the top when needed and
    /// removed when its last key goes.
    public static func setting(_ key: String, to value: Value?, in text: String) -> String {
        let crlf = text.contains("\r\n")
        let newline = crlf ? "\r\n" : "\n"
        let rendered = value.map { "\(key): \(render($0))" }
        guard parse(text) != nil else {
            guard let rendered else { return text }
            return "---\(newline)\(rendered)\(newline)---\(newline)" + text
        }
        // Lines below are split on "\n" (UTF-16), so CRLF lines keep their "\r".
        let renderedLine = rendered.map { crlf ? $0 + "\r" : $0 }

        // Rebuild only the lines of the block, replacing the key's lines.
        let fm = parse(text)!
        let block = String(text[fm.range])
        var lines = block.components(separatedBy: "\n")   // keeps "\r" on CRLF lines
        var i = 1
        var replaced = false
        while i < lines.count - 1 {
            let content = lines[i].trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if content == "---" || content == "..." { break }
            if Self.keyOfLine(content) == key {
                // Drop the key line and any indented / `- ` continuation lines.
                var end = i + 1
                while end < lines.count - 1 {
                    let next = lines[end].trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
                    guard next.hasPrefix(" ") || next.hasPrefix("\t") || next.hasPrefix("- ") || next == "-" else { break }
                    end += 1
                }
                let replacement = renderedLine.map { [$0] } ?? []
                lines.replaceSubrange(i..<end, with: replacement)
                replaced = true
                break
            }
            i += 1
        }
        if !replaced, let renderedLine {
            // Insert before the closing delimiter.
            let close = lines.lastIndex { let c = $0.trimmingCharacters(in: CharacterSet(charactersIn: "\r")); return c == "---" || c == "..." } ?? lines.count - 1
            lines.insert(renderedLine, at: close)
        }
        let newBlock = lines.joined(separator: "\n")
        let result = newBlock + text[fm.range.upperBound...]
        if let parsed = parse(result), parsed.fields.isEmpty {
            return String(result[parsed.range.upperBound...])
        }
        return result
    }

    // MARK: Helpers

    private static func keyOfLine(_ line: String) -> String? {
        guard !line.hasPrefix(" "), !line.hasPrefix("\t"), let colon = line.firstIndex(of: ":") else { return nil }
        return line[..<colon].trimmingCharacters(in: .whitespaces)
    }

    private static func render(_ value: Value) -> String {
        switch value {
        case .scalar(let s): return needsQuotes(s) ? quote(s) : s
        case .list(let items): return "[" + items.map { needsQuotes($0) || $0.contains(",") ? quote($0) : $0 }.joined(separator: ", ") + "]"
        }
    }

    private static func needsQuotes(_ s: String) -> Bool {
        s.isEmpty || s.first == " " || s.last == " " || s.contains(": ") || s.contains(" #")
            || "[]{}&*!|>'\"%@`#".contains(s.first!)
    }

    private static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func unquote(_ s: String) -> String {
        if s.count >= 2, s.hasPrefix("\""), s.hasSuffix("\"") {
            return String(s.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
        }
        if s.count >= 2, s.hasPrefix("'"), s.hasSuffix("'") {
            return String(s.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        // A trailing ` # comment` isn't part of a plain scalar.
        if let comment = s.range(of: " #") { return String(s[..<comment.lowerBound]).trimmingCharacters(in: .whitespaces) }
        return s
    }

    static func tagName(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("#") { t.removeFirst() }
        return t.lowercased()
    }

    static func parseDate(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withFullDate]
        if let d = iso.date(from: String(s.prefix(10))) { return d }
        return nil
    }

    /// The line starting at `start` (without its terminator) and where the next begins.
    private static func line(in text: String, from start: String.Index) -> (content: Substring, next: String.Index)? {
        guard start < text.endIndex else { return nil }
        // "\r\n" is a single Character in Swift.
        if let nl = text[start...].firstIndex(where: { $0 == "\n" || $0 == "\r\n" }) {
            return (text[start..<nl], text.index(after: nl))
        }
        return (text[start...], text.endIndex)
    }
}

private extension StringProtocol {
    var trimmingTrailingSpace: String {
        var s = String(self)
        while let last = s.last, last == " " || last == "\t" || last == "\r" { s.removeLast() }
        return s
    }
}
