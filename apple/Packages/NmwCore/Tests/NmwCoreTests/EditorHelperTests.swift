//
//  EditorHelperTests.swift
//  NmwCoreTests
//
//  Word counts and `[[` note-link completion.
//

import Foundation
import Testing
@testable import NmwCore

@Suite("Text statistics")
struct TextStatisticsTests {

    @Test func plainProse() {
        let stats = TextStatistics(markdown: "Hello world.\nSecond line here")
        #expect(stats.words == 5)
        #expect(stats.characters == "Hello world.".count + "Second line here".count)
        #expect(TextStatistics(markdown: "") == TextStatistics(words: 0, characters: 0))
    }

    @Test func frontmatterAndMarkersDontCount() {
        let text = """
        ---
        tags: [a, b]
        title: Not counted
        ---
        # A **bold** title
        - [ ] buy *milk*
        > quoted `code`
        See [the guide](Guides/Setup%20Guide.md){.preview} and ![photo](a.png){.medium}.
        <!-- Sheet -->
        ---
        """
        let stats = TextStatistics(markdown: text)
        // "A bold title", "buy milk", "quoted code", "See the guide and ."
        #expect(stats.words == 3 + 2 + 2 + 4)
        #expect(stats.characters == "A bold title".count + "buy milk".count + "quoted code".count + "See the guide and .".count)
    }

    @Test func codeCountsButNotItsFences() {
        let stats = TextStatistics(markdown: "```swift\n    let x = 1\n```\nDone")
        #expect(stats.words == 4)   // let, x, 1, Done
        #expect(stats.characters == "let x = 1".count + 4)
    }

    @Test func tablesCountCellText() {
        let stats = TextStatistics(markdown: "| Name | Age |\n|---|---|\n| Ann | 3 |")
        #expect(stats.words == 4)
    }
}

@Suite("Note link completion")
struct NoteLinkCompletionTests {

    @Test func triggersOnATypedDoubleBracket() {
        #expect(NoteLinkCompletion.trigger(in: "See [[", caret: 6) == 4)
        // The editor auto-closes it: `[[]]` with the caret inside.
        #expect(NoteLinkCompletion.trigger(in: "See [[]] later", caret: 6) == 4)
        #expect(NoteLinkCompletion.trigger(in: "[[", caret: 2) == 0)
        #expect(NoteLinkCompletion.trigger(in: "See [x", caret: 6) == nil)
        #expect(NoteLinkCompletion.trigger(in: "[", caret: 1) == nil)
    }

    @Test func notAfterAnotherBracketAnImageOrAnEscape() {
        #expect(NoteLinkCompletion.trigger(in: "[[[", caret: 3) == nil)
        #expect(NoteLinkCompletion.trigger(in: "![[", caret: 3) == nil)
        #expect(NoteLinkCompletion.trigger(in: "\\[[", caret: 3) == nil)
    }

    @Test func notInCodeOrFrontmatter() {
        #expect(NoteLinkCompletion.trigger(in: "```\n[[", caret: 6) == nil)
        #expect(NoteLinkCompletion.trigger(in: "```\nx\n```\n[[", caret: 12) == 10)
        #expect(NoteLinkCompletion.trigger(in: "a `[[", caret: 5) == nil)
        #expect(NoteLinkCompletion.trigger(in: "a `b` [[", caret: 8) == 6)
        #expect(NoteLinkCompletion.trigger(in: "---\ntags: [[\n---\n", caret: 12) == nil)
    }

    @Test func replacementCoversTheQueryAndTheClosingBrackets() {
        #expect(NoteLinkCompletion.replacementRange(in: "See [[]] later", anchor: 4, caret: 6) == NSRange(location: 4, length: 4))
        #expect(NoteLinkCompletion.replacementRange(in: "See [[pla", anchor: 4, caret: 9) == NSRange(location: 4, length: 5))
        #expect(NoteLinkCompletion.replacementRange(in: "See [[pla]]", anchor: 4, caret: 9) == NSRange(location: 4, length: 7))
        // The brackets were deleted meanwhile.
        #expect(NoteLinkCompletion.replacementRange(in: "See x", anchor: 4, caret: 5) == nil)
        #expect(NoteLinkCompletion.replacementRange(in: "See [[", anchor: 4, caret: 9) == nil)
    }

    @Test func linksAreStandardRelativeMarkdown() {
        let note = URL(fileURLWithPath: "/nb/Projects/Idea.md")
        let target = URL(fileURLWithPath: "/nb/Guides/Setup Guide (v2).md")
        #expect(NoteLinkCompletion.markdownLink(title: "Setup [v2]", from: note, to: target)
                == "[Setup \\[v2\\]](../Guides/Setup%20Guide%20%28v2%29.md)")
    }
}
