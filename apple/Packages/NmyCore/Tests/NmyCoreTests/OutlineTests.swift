//
//  OutlineTests.swift
//  NmyCoreTests
//

import Foundation
import Testing
@testable import NmyCore

@Suite("Note outline")
struct NoteOutlineTests {

    @Test func atxAndSetextHeadingsWithRanges() {
        let text = "---\ntitle: x\n---\n# Café **plan**\nintro\n## Steps ##\n```\n# not one\n```\nSetext two\n---\n  ### Three\n"
        let headings = NoteOutline.headings(in: text)
        #expect(headings.map(\.title) == ["Café plan", "Steps", "Setext two", "Three"])
        #expect(headings.map(\.level) == [1, 2, 2, 3])
        let ns = text as NSString
        #expect(ns.substring(with: headings[0].range) == "# Café **plan**")
        #expect(ns.substring(with: headings[2].range) == "Setext two")
        #expect(ns.substring(with: headings[3].range) == "  ### Three")
    }

    @Test func listItemsAndRulesAreNotSetextHeadings() {
        #expect(NoteOutline.headings(in: "- item\n---\n").isEmpty)
        #expect(NoteOutline.headings(in: "\n---\n").isEmpty)
        #expect(NoteOutline.headings(in: "#nottag\n#7 x\n").isEmpty)
    }

    @Test func crlfRangesExcludeTheLineBreak() {
        let text = "# A\r\nb\r\n## C\r\n"
        let headings = NoteOutline.headings(in: text)
        #expect(headings.map { (text as NSString).substring(with: $0.range) } == ["# A", "## C"])
    }
}
