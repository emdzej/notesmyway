//
//  LinkScanner.swift
//  NmyCore
//
//  Finds link and image destinations in markdown with their positions, so
//  they can be both indexed and rewritten in place (renames, moves).
//  Skips frontmatter, fenced code and code spans.
//

import Foundation

struct LinkOccurrence: Equatable {
    /// The destination as written in the text (inside `<…>` when angled).
    let range: Range<String.Index>
    /// The destination with backslash escapes removed.
    let destination: String
    let kind: NoteLink.Kind
}

/// Tracks fenced code blocks line by line.
struct FenceTracker {
    private var open: (char: Character, count: Int)?

    /// True for fence lines and lines inside a fence.
    mutating func isCode(_ line: Substring) -> Bool {
        let indent = line.prefix(while: { $0 == " " }).count
        let trimmed = line.dropFirst(indent)
        if let fence = open {
            let run = trimmed.prefix(while: { $0 == fence.char })
            if run.count >= fence.count, trimmed.dropFirst(run.count).allSatisfy(\.isWhitespace) { open = nil }
            return true
        }
        if indent <= 3, let c = trimmed.first, c == "`" || c == "~" {
            let run = trimmed.prefix(while: { $0 == c }).count
            if run >= 3, !(c == "`" && trimmed.dropFirst(run).contains("`")) {
                open = (c, run)
                return true
            }
        }
        return false
    }
}

enum LinkScanner {

    /// Every link in a note's full text.
    static func occurrences(in text: String) -> [LinkOccurrence] {
        var fence = FenceTracker()
        var result: [LinkOccurrence] = []
        for line in Frontmatter.body(of: text).split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            if fence.isCode(line) { continue }
            result += occurrences(inLine: line)
        }
        return result
    }

    /// Links on one (non-code) line: a reference definition, or inline links.
    static func occurrences(inLine line: Substring) -> [LinkOccurrence] {
        if let definition = referenceDefinition(line) { return [definition] }
        return inline(line, excluding: codeSpans(in: line))
    }

    /// `[id]: destination "title"` (not footnotes, `[^1]:`).
    static func referenceDefinition(_ line: Substring) -> LinkOccurrence? {
        let s = line.drop(while: { $0 == " " })
        guard s.hasPrefix("["), let close = s.firstIndex(of: "]"),
              let colon = s.index(close, offsetBy: 1, limitedBy: s.endIndex), colon < s.endIndex, s[colon] == ":" else { return nil }
        let label = s[s.index(after: s.startIndex)..<close]
        guard !label.isEmpty, !label.hasPrefix("^") else { return nil }
        var start = s.index(after: colon)
        while start < s.endIndex, s[start] == " " || s[start] == "\t" { start = s.index(after: start) }
        guard start < s.endIndex else { return nil }
        if s[start] == "<" {
            let inner = s.index(after: start)
            guard let end = s[inner...].firstIndex(of: ">"), end > inner else { return nil }
            return LinkOccurrence(range: inner..<end, destination: String(s[inner..<end]), kind: .link)
        }
        let end = s[start...].firstIndex(where: \.isWhitespace) ?? s.endIndex
        return LinkOccurrence(range: start..<end, destination: String(s[start..<end]), kind: .link)
    }

    /// `[text](dest)` / `![alt](dest)`, including images nested in link text.
    static func inline(_ s: Substring, excluding code: [Range<String.Index>]) -> [LinkOccurrence] {
        var result: [LinkOccurrence] = []
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "\\" { i = s.index(i, offsetBy: 2, limitedBy: s.endIndex) ?? s.endIndex; continue }
            guard c == "[", !code.contains(where: { $0.contains(i) }) else { i = s.index(after: i); continue }
            let isImage = i > s.startIndex && s[s.index(before: i)] == "!"

            var depth = 0
            var j = i
            var close: String.Index?
            while j < s.endIndex {
                let cj = s[j]
                if cj == "\\" { j = s.index(j, offsetBy: 2, limitedBy: s.endIndex) ?? s.endIndex; continue }
                if cj == "[" { depth += 1 } else if cj == "]" { depth -= 1; if depth == 0 { close = j; break } }
                j = s.index(after: j)
            }
            guard let close else { i = s.index(after: i); continue }
            let paren = s.index(after: close)
            guard paren < s.endIndex, s[paren] == "(", let dest = destination(s, from: s.index(after: paren)) else {
                i = s.index(after: i)
                continue
            }
            result.append(LinkOccurrence(range: dest.range, destination: dest.value, kind: isImage ? .image : .link))
            result += inline(s[s.index(after: i)..<close], excluding: code)
            i = s.index(after: dest.closeParen)
        }
        return result
    }

    /// The destination after `(`, and the closing `)`.
    private static func destination(_ s: Substring, from start: String.Index) -> (range: Range<String.Index>, value: String, closeParen: String.Index)? {
        var k = start
        while k < s.endIndex, s[k] == " " { k = s.index(after: k) }
        guard k < s.endIndex else { return nil }
        let range: Range<String.Index>
        var value = ""
        if s[k] == "<" {
            let inner = s.index(after: k)
            guard let end = s[inner...].firstIndex(where: { $0 == ">" || $0.isNewline }), s[end] == ">" else { return nil }
            range = inner..<end
            value = String(s[range])
            k = s.index(after: end)
        } else {
            let begin = k
            var depth = 0
            while k < s.endIndex {
                let c = s[k]
                if c == "\\", let next = s.index(k, offsetBy: 1, limitedBy: s.endIndex), next < s.endIndex {
                    value.append(s[next])
                    k = s.index(after: next)
                    continue
                }
                if c.isWhitespace { break }
                if c == "(" { depth += 1 }
                if c == ")" { if depth == 0 { break }; depth -= 1 }
                value.append(c)
                k = s.index(after: k)
            }
            range = begin..<k
        }
        // Optional title, then `)`.
        while k < s.endIndex, s[k] != ")" {
            if s[k] == "\"" || s[k] == "'" {
                let quote = s[k]
                k = s.index(after: k)
                while k < s.endIndex, s[k] != quote { k = s.index(after: k) }
                if k == s.endIndex { return nil }
            }
            k = s.index(after: k)
        }
        guard k < s.endIndex, !value.isEmpty else { return nil }
        return (range, value, k)
    }

    /// Ranges of `code spans` on a line.
    static func codeSpans(in s: Substring) -> [Range<String.Index>] {
        var spans: [Range<String.Index>] = []
        var i = s.startIndex
        while i < s.endIndex {
            guard s[i] == "`" else { i = s.index(after: i); continue }
            let run = s[i...].prefix(while: { $0 == "`" })
            let marker = String(run)
            if let close = s[run.endIndex...].range(of: marker) {
                spans.append(i..<close.upperBound)
                i = close.upperBound
            } else {
                i = run.endIndex
            }
        }
        return spans
    }
}

/// Building link destinations between files.
public enum LinkPath {
    /// The relative path from the folder of `note` to `target`
    /// (`../Guides/Setup Guide.md`), unencoded.
    public static func relative(from note: URL, to target: URL) -> String {
        let from = note.standardizedFileURL.deletingLastPathComponent().pathComponents
        let to = target.standardizedFileURL.pathComponents
        var common = 0
        while common < from.count, common < to.count - 1, from[common] == to[common] { common += 1 }
        let ups = Array(repeating: "..", count: from.count - common)
        return (ups + to[common...]).joined(separator: "/")
    }

    /// Percent-encodes a path for a link destination; `/` stays readable,
    /// spaces and parentheses are encoded (matches the editor's file drops).
    public static func encode(_ path: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "()<> ")
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    }
}
