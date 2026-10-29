//
//  NoteOutline.swift
//  NmyCore
//
//  A note's headings with their positions, for the outline panel. Ranges
//  are UTF-16 (`NSRange`), which is what the editor selects and scrolls by.
//

import Foundation

public struct NoteHeading: Equatable, Hashable, Sendable, Identifiable {
    public var id: Int { range.location }
    public let level: Int
    /// Heading text with inline markdown removed.
    public let title: String
    /// The heading line, without its line break.
    public let range: NSRange
}

public enum NoteOutline {

    /// ATX (`## Title`) and setext (`Title` + `===` / `---`) headings outside
    /// frontmatter and fenced code.
    public static func headings(in text: String) -> [NoteHeading] {
        let ns = text as NSString
        let bodyStart = Frontmatter.parse(text).map { NSRange($0.range, in: text).upperBound } ?? 0
        var headings: [NoteHeading] = []
        var fence = FenceTracker()
        var previous: (range: NSRange, text: Substring)?
        var location = bodyStart
        while location < ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: location, length: 0))
            var contentRange = lineRange
            while contentRange.length > 0, let scalar = UnicodeScalar(ns.character(at: NSMaxRange(contentRange) - 1)),
                  CharacterSet.newlines.contains(scalar) {
                contentRange.length -= 1
            }
            let line = Substring(ns.substring(with: contentRange))
            location = NSMaxRange(lineRange)

            if fence.isCode(line) { previous = nil; continue }
            let trimmed = line.drop(while: { $0 == " " })
            let indent = line.count - trimmed.count

            if indent <= 3, let level = (1...6).first(where: { MarkdownScan.atxHeading(trimmed, level: $0) != nil }),
               let title = MarkdownScan.atxHeading(trimmed, level: level) {
                headings.append(NoteHeading(level: level, title: MarkdownScan.plainText(title), range: contentRange))
                previous = nil
                continue
            }
            // Setext underline turns the previous paragraph line into a heading.
            let underline = trimmed.trimmingCharacters(in: .whitespaces)
            if let prev = previous, indent <= 3, !underline.isEmpty,
               underline.allSatisfy({ $0 == "=" }) || underline.allSatisfy({ $0 == "-" }) {
                let title = MarkdownScan.plainText(String(prev.text.trimmingCharacters(in: .whitespaces)))
                headings.append(NoteHeading(level: underline.first == "=" ? 1 : 2, title: title, range: prev.range))
                previous = nil
                continue
            }
            let isParagraphLine = !trimmed.isEmpty && !trimmed.hasPrefix(">") && !trimmed.hasPrefix("|")
                && !trimmed.hasPrefix("- ") && !trimmed.hasPrefix("* ") && !trimmed.hasPrefix("+ ")
            previous = isParagraphLine ? (contentRange, line) : nil
        }
        return headings
    }
}
