//
//  TextStatistics.swift
//  NmwCore
//
//  Word and character counts for the inspector, on the text as it reads:
//  frontmatter, fence lines and markdown markers don't count, link text
//  does, link destinations and images don't. Code inside fences counts.
//

import Foundation

public struct TextStatistics: Equatable, Sendable {
    public let words: Int
    /// Characters without line breaks.
    public let characters: Int

    public init(words: Int, characters: Int) {
        self.words = words
        self.characters = characters
    }

    /// Counts a note's full text (frontmatter skipped), or a selection of it.
    public init(markdown: String) {
        var fence = FenceTracker()
        var words = 0, characters = 0
        for rawLine in Frontmatter.body(of: markdown).split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let text: String
            if fence.isCode(rawLine) {
                let trimmed = rawLine.drop(while: { $0 == " " })
                if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { continue }
                text = rawLine.trimmingCharacters(in: .whitespaces)
            } else {
                let bare = rawLine.trimmingCharacters(in: .whitespaces)
                if bare.hasPrefix("<!--"), bare.hasSuffix("-->") { continue }
                // Code spans keep their text; only the backticks go.
                let line = String(rawLine).replacingOccurrences(of: "`", with: "")
                text = MarkdownScan.plainText(MarkdownScan.strippingBlockMarkers(line))
            }
            guard !text.isEmpty else { continue }
            characters += text.count
            text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
                words += 1
            }
        }
        self.init(words: words, characters: characters)
    }
}
