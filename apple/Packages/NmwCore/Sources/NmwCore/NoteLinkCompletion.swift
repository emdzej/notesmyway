//
//  NoteLinkCompletion.swift
//  NmwCore
//
//  Typing `[[` offers a note to link to. nmw writes standard markdown links
//  only, so the picked note replaces the `[[` (and the `]]` the editor
//  auto-closes it with) by `[Title](relative/path.md)`; no wikilink stays in
//  the file. Ranges are UTF-16, as the editor's.
//

import Foundation

public enum NoteLinkCompletion {

    /// Where a `[[` that ends at `caret` starts, or nil when there's none
    /// there or it shouldn't open the picker: a third `[`, an image (`![[`),
    /// an escape, frontmatter, or code.
    public static func trigger(in text: String, caret: Int) -> Int? {
        let ns = text as NSString
        guard caret >= 2, caret <= ns.length,
              ns.substring(with: NSRange(location: caret - 2, length: 2)) == "[[" else { return nil }
        let anchor = caret - 2
        if anchor > 0, ["[", "!", "\\"].contains(ns.substring(with: NSRange(location: anchor - 1, length: 1))) { return nil }
        return isCode(at: anchor, in: text) ? nil : anchor
    }

    /// The text the picked link replaces: from the `[[` at `anchor` to
    /// `caret`, plus a `]]` right after. Nil when that `[[` is gone (the
    /// text changed meanwhile).
    public static func replacementRange(in text: String, anchor: Int, caret: Int) -> NSRange? {
        let ns = text as NSString
        guard anchor >= 0, caret >= anchor + 2, caret <= ns.length,
              ns.substring(with: NSRange(location: anchor, length: 2)) == "[[" else { return nil }
        var end = caret
        if end + 2 <= ns.length, ns.substring(with: NSRange(location: end, length: 2)) == "]]" { end += 2 }
        return NSRange(location: anchor, length: end - anchor)
    }

    /// A standard markdown link from the note at `noteURL` to `target`, as
    /// "Link to Note" (⌘L) writes it.
    public static func markdownLink(title: String, from noteURL: URL, to target: URL) -> String {
        let destination = LinkPath.encode(LinkPath.relative(from: noteURL, to: target))
        let label = title.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
        return "[\(label)](\(destination))"
    }

    /// Inside frontmatter, a fenced block or a code span (an open backtick
    /// run earlier on the line counts: the span is still being typed).
    static func isCode(at location: Int, in text: String) -> Bool {
        let ns = text as NSString
        let bodyStart = Frontmatter.parse(text).map { NSRange($0.range, in: text).upperBound } ?? 0
        if location < bodyStart { return true }
        var fence = FenceTracker()
        var lineStart = bodyStart
        while lineStart < ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: lineStart, length: 0))
            let line = Substring(ns.substring(with: lineRange).trimmingCharacters(in: .newlines))
            let isCode = fence.isCode(line)
            if location < NSMaxRange(lineRange) || NSMaxRange(lineRange) >= ns.length {
                if isCode { return true }
                let before = ns.substring(with: NSRange(location: lineRange.location, length: location - lineRange.location))
                return openBacktickRun(in: before)
            }
            lineStart = NSMaxRange(lineRange)
        }
        return false
    }

    /// True when `line` ends inside a code span (or an unclosed backtick run).
    private static func openBacktickRun(in line: String) -> Bool {
        var i = line.startIndex
        while i < line.endIndex {
            guard line[i] == "`" else { i = line.index(after: i); continue }
            let run = line[i...].prefix(while: { $0 == "`" })
            guard let close = line[run.endIndex...].range(of: String(run)) else { return true }
            i = close.upperBound
        }
        return false
    }
}
