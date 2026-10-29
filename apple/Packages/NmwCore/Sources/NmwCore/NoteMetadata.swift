//
//  NoteMetadata.swift
//  NmwCore
//
//  What nmw extracts from a note's markdown: title, snippet, tags, links,
//  first image, and the plain text that full-text search indexes. Works on
//  text alone, so notebook notes and standalone files are treated the same.
//

import Foundation

public struct NoteLink: Equatable, Hashable, Sendable {
    public enum Kind: String, Sendable { case link, image }
    /// The destination as written (percent-encoded, maybe with `#fragment`).
    public let destination: String
    public let kind: Kind

    public init(destination: String, kind: Kind) {
        self.destination = destination
        self.kind = kind
    }
}

public struct NoteMetadata: Equatable, Sendable {
    public var title: String
    /// Up to ~200 characters of body text after the title, markdown stripped.
    public var snippet: String
    /// Lowercased, unique, sorted: frontmatter `tags` plus inline `#tags`.
    public var tags: [String]
    public var links: [NoteLink]
    /// Destination of the first image, as written.
    public var firstImage: String?
    public var pinned: Bool
    public var created: Date?
    /// Checklist items (`- [ ]` / `- [x]`) outside code: checked and total.
    public var tasksDone = 0
    public var tasksTotal = 0
    /// Body text for full-text search (frontmatter and code fences removed).
    public var searchText: String

    /// Extracts metadata; `fileName` (without extension) is the title fallback.
    public init(markdown: String, fileName: String) {
        let frontmatter = Frontmatter.parse(markdown)
        let body = Frontmatter.body(of: markdown)
        let scan = MarkdownScan(body)

        title = scan.title ?? fileName
        snippet = scan.snippet
        var tagSet = Set(frontmatter?.tags ?? [])
        tagSet.formUnion(scan.tags)
        tags = tagSet.sorted()
        links = scan.links
        firstImage = scan.links.first { $0.kind == .image }?.destination
        pinned = frontmatter?.pinned ?? false
        (tasksDone, tasksTotal) = Self.taskCounts(in: body)
        created = frontmatter?.created
        searchText = scan.searchText
    }
}

/// One pass over the body lines, skipping fenced code.
struct MarkdownScan {
    private(set) var title: String?
    private(set) var snippet = ""
    private(set) var tags: Set<String> = []
    private(set) var links: [NoteLink] = []
    private(set) var searchText = ""

    init(_ body: Substring) {
        let lines = body.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        var fence = FenceTracker()
        var titleLine: Int?
        var snippetParts: [String] = []
        var snippetLength = 0
        var search: [String] = []

        for (index, rawLine) in lines.enumerated() {
            if fence.isCode(rawLine) { continue }
            let line = String(rawLine)
            let trimmed = line.drop(while: { $0 == " " })

            let found = LinkScanner.occurrences(inLine: rawLine)
            links += found.map { NoteLink(destination: $0.destination, kind: $0.kind) }
            if LinkScanner.referenceDefinition(rawLine) != nil { continue }
            // `<!-- name -->` (a formula sheet name) isn't prose.
            let bare = trimmed.trimmingCharacters(in: .whitespaces)
            if bare.hasPrefix("<!--"), bare.hasSuffix("-->") { continue }

            let prose = Self.removingCodeSpans(line)
            tags.formUnion(Self.inlineTags(in: prose))

            if title == nil, titleLine == nil {
                if let h1 = Self.atxHeading(trimmed, level: 1) {
                    title = Self.plainText(h1)
                    titleLine = index
                    search.append(title!)
                    continue
                }
                if index + 1 < lines.count, !trimmed.isEmpty, Self.isSetextH1Underline(lines[index + 1]) {
                    title = Self.plainText(String(trimmed))
                    titleLine = index + 1
                    search.append(title!)
                    continue
                }
            }
            if index == titleLine { continue }

            let text = Self.plainText(Self.strippingBlockMarkers(prose))
            guard !text.isEmpty else { continue }
            search.append(text)
            if snippetLength < 200 {
                snippetParts.append(text)
                snippetLength += text.count + 1
            }
        }
        let joined = snippetParts.joined(separator: " ")
        snippet = joined.count > 200 ? String(joined.prefix(200)).trimmingCharacters(in: .whitespaces) + "…" : joined
        searchText = search.joined(separator: "\n")
    }

    // MARK: Block helpers

    static func atxHeading(_ line: Substring, level: Int) -> String? {
        let hashes = line.prefix(while: { $0 == "#" })
        guard hashes.count == level else { return nil }
        let rest = line.dropFirst(level)
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        // Optional closing `#`s.
        if let closing = text.range(of: #"\s+#+$"#, options: .regularExpression) { text.removeSubrange(closing) }
        else if text.allSatisfy({ $0 == "#" }) { text = "" }
        return text.isEmpty ? nil : text
    }

    static func isSetextH1Underline(_ line: Substring) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return !t.isEmpty && t.allSatisfy { $0 == "=" }
    }

    /// Drops heading hashes, quote markers, list bullets and task boxes.
    static func strippingBlockMarkers(_ line: String) -> String {
        var s = Substring(line).drop(while: { $0 == " " || $0 == "\t" })
        while s.hasPrefix(">") { s = s.dropFirst().drop(while: { $0 == " " }) }
        let hashes = s.prefix(while: { $0 == "#" })
        if (1...6).contains(hashes.count), s.dropFirst(hashes.count).first == " " { s = s.dropFirst(hashes.count + 1) }
        if let first = s.first, "-*+".contains(first), s.dropFirst().first == " " { s = s.dropFirst(2) }
        else if let dot = s.firstIndex(where: { $0 == "." || $0 == ")" }), s[..<dot].allSatisfy(\.isNumber), !s[..<dot].isEmpty,
                s[s.index(after: dot)...].first == " " {
            s = s[s.index(dot, offsetBy: 2)...]
        }
        for box in ["[ ] ", "[x] ", "[X] "] where s.hasPrefix(box) { s = s.dropFirst(box.count) }
        // Table rows: keep cell text, drop pipes; delimiter rows vanish.
        if s.hasPrefix("|") {
            let cells = s.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            if cells.allSatisfy({ $0.allSatisfy { "-: ".contains($0) } }) { return "" }
            return cells.filter { !$0.isEmpty }.joined(separator: " ")
        }
        if s.allSatisfy({ "-*_= ".contains($0) }) { return "" }   // rules, setext underlines
        return String(s)
    }

    // MARK: Inline helpers

    static func removingCodeSpans(_ line: String) -> String {
        guard line.contains("`") else { return line }
        var out = ""
        var i = line.startIndex
        while i < line.endIndex {
            if line[i] == "`" {
                let run = line[i...].prefix(while: { $0 == "`" }).count
                let afterOpen = line.index(i, offsetBy: run)
                let marker = String(repeating: "`", count: run)
                if let close = line[afterOpen...].range(of: marker) {
                    out += " "
                    i = close.upperBound
                    continue
                }
                out += line[i..<afterOpen]
                i = afterOpen
                continue
            }
            out.append(line[i])
            i = line.index(after: i)
        }
        return out
    }

    /// `#tag` and `#nested/tag` after whitespace or at line start; must contain a non-digit.
    static func inlineTags(in line: String) -> Set<String> {
        guard line.contains("#") else { return [] }
        var tags: Set<String> = []
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            if chars[i] == "#", i == 0 || chars[i - 1].isWhitespace {
                var j = i + 1
                while j < chars.count, chars[j].isLetter || chars[j].isNumber || "_-/".contains(chars[j]) { j += 1 }
                var tag = String(chars[(i + 1)..<j])
                while tag.hasSuffix("/") { tag.removeLast() }
                if !tag.isEmpty, !tag.allSatisfy(\.isNumber) { tags.insert(tag.lowercased()) }
                i = j
                continue
            }
            i += 1
        }
        return tags
    }

    /// Inline markdown to readable text: links → their text, images and
    /// attribute blocks dropped, emphasis markers removed.
    static func plainText(_ line: String) -> String {
        var s = line
        s = s.replacingOccurrences(of: #"!\[[^\]]*\]\([^)]*\)(\{[^}]*\})?"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)(\{[^}]*\})?"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\[([^\]]*)\]\[[^\]]*\]"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<(https?://[^>]+)>"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(\*\*|__|~~|\*|(?<![A-Za-z0-9])_|_(?![A-Za-z0-9]))"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\\([\\`*_{}\[\]()#+\-.!|~])"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
    }
}

extension NoteMetadata {
    private static let taskItem = try! NSRegularExpression(pattern: #"^[ \t]*(?:[-*+]|\d{1,9}[.)])[ \t]+\[([ xX])\](?:[ \t]|$)"#)

    static func taskCounts(in body: Substring) -> (done: Int, total: Int) {
        var fence = FenceTracker()
        var done = 0, total = 0
        for line in body.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            if fence.isCode(line) { continue }
            let text = String(line)
            let ns = text as NSString
            guard let m = taskItem.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { continue }
            total += 1
            if ns.substring(with: m.range(at: 1)) != " " { done += 1 }
        }
        return (done, total)
    }
}

