//
//  FrontmatterTests.swift
//  NmwCoreTests
//

import Foundation
import Testing
@testable import NmwCore

@Suite("Frontmatter")
struct FrontmatterTests {

    @Test func parsesScalarsAndBothListForms() throws {
        let text = """
            ---
            tags: [Project, "idea"]
            pinned: true
            created: 2026-10-29T10:00:00Z
            aliases:
              - one
              - two
            nested:
              key: value
            ---
            # Body
            """
        let fm = try #require(Frontmatter.parse(text))
        #expect(fm.tags == ["project", "idea"])
        #expect(fm.pinned)
        #expect(fm.created == ISO8601DateFormatter().date(from: "2026-10-29T10:00:00Z"))
        #expect(fm["aliases"] == .list(["one", "two"]))
        #expect(Frontmatter.body(of: text) == "# Body")
    }

    @Test func notFrontmatter() {
        #expect(Frontmatter.parse("# Title\n---\n") == nil)
        #expect(Frontmatter.parse("---\nunclosed: yes\n") == nil)
        #expect(Frontmatter.body(of: "plain") == "plain")
    }

    @Test func crlfAndBOM() throws {
        let text = "\u{FEFF}---\r\ntags: a, b\r\n---\r\nBody"
        let fm = try #require(Frontmatter.parse(text))
        #expect(fm.tags == ["a", "b"])
        #expect(Frontmatter.body(of: text) == "Body")
    }

    @Test func settingAKeyOnlyTouchesItsLines() {
        let text = "---\ntitle: x   # kept\npinned: false\nother: [a]\n---\nBody\n"
        #expect(Frontmatter.setting("pinned", to: .scalar("true"), in: text)
                == "---\ntitle: x   # kept\npinned: true\nother: [a]\n---\nBody\n")
        #expect(Frontmatter.setting("tags", to: .list(["a b", "c"]), in: text)
                == "---\ntitle: x   # kept\npinned: false\nother: [a]\ntags: [a b, c]\n---\nBody\n")
        #expect(Frontmatter.setting("pinned", to: nil, in: text)
                == "---\ntitle: x   # kept\nother: [a]\n---\nBody\n")
    }

    @Test func blockListsAreReplacedWhole() {
        let text = "---\ntags:\n  - a\n  - b\nx: 1\n---\n"
        #expect(Frontmatter.setting("tags", to: .list(["c"]), in: text) == "---\ntags: [c]\nx: 1\n---\n")
    }

    @Test func addsAndRemovesTheBlock() {
        let added = Frontmatter.setting("pinned", to: .scalar("true"), in: "# Note\n")
        #expect(added == "---\npinned: true\n---\n# Note\n")
        #expect(Frontmatter.setting("pinned", to: nil, in: added) == "# Note\n")
        #expect(Frontmatter.setting("pinned", to: nil, in: "# Note\n") == "# Note\n")
    }

    @Test func crlfIsKeptWhenEditing() {
        let text = "---\r\npinned: false\r\n---\r\nBody"
        #expect(Frontmatter.setting("pinned", to: .scalar("true"), in: text) == "---\r\npinned: true\r\n---\r\nBody")
        #expect(Frontmatter.setting("x", to: .scalar("1"), in: text) == "---\r\npinned: false\r\nx: 1\r\n---\r\nBody")
    }

    @Test func valuesThatNeedQuotesGetThem() {
        #expect(Frontmatter.setting("title", to: .scalar("a: b"), in: "") == "---\ntitle: \"a: b\"\n---\n")
        #expect(Frontmatter.parse(Frontmatter.setting("title", to: .scalar("say \"hi\""), in: ""))?["title"] == .scalar("say \"hi\""))
    }
}
