//
//  NoteMetadataTests.swift
//  NmyCoreTests
//

import Foundation
import Testing
@testable import NmyCore

@Suite("Note metadata")
struct NoteMetadataTests {

    private func meta(_ markdown: String, file: String = "File Name") -> NoteMetadata {
        NoteMetadata(markdown: markdown, fileName: file)
    }

    @Test func titleIsTheFirstH1ElseTheFileName() {
        #expect(meta("Intro\n# The **Big** Idea #\nBody").title == "The Big Idea")
        #expect(meta("Setext Title\n===\nBody").title == "Setext Title")
        #expect(meta("## Only H2\nBody").title == "File Name")
        #expect(meta("```\n# not a title\n```\n").title == "File Name")
        #expect(meta("---\ntags: [a]\n---\n# After Frontmatter").title == "After Frontmatter")
    }

    @Test func snippetIsPlainBodyTextAfterTheTitle() {
        let m = meta("""
            # Title
            Some **bold** and [a link](x.md){.preview} here.
            ![](pic.png)
            - [ ] a task
            > quoted
            | a | b |
            |---|---|
            """)
        #expect(m.snippet == "Some bold and a link here. a task quoted a b")
    }

    @Test func longSnippetsAreCut() {
        let m = meta("# T\n" + String(repeating: "word ", count: 100))
        #expect(m.snippet.count <= 201)
        #expect(m.snippet.hasSuffix("…"))
    }

    @Test func tagsComeFromFrontmatterAndText() {
        let m = meta("""
            ---
            tags: [Project]
            ---
            # Heading is not a tag
            Text #idea and #nested/Tag, not#this, not #123, `#code`
            ```
            #fenced
            ```
            """)
        #expect(m.tags == ["idea", "nested/tag", "project"])
    }

    @Test func linksImagesAndReferences() {
        let m = meta("""
            See [Plan](Projects/Plan%20B.md#goals "title") and ![chart](_attachments/c.png){.small}.
            [![badge](b.svg)](https://ci.example.com)
            Not a link: `[x](y.md)` and \\[z](w.md)
            [ref]: <Other Note.md>
            [^1]: footnote
            """)
        #expect(m.links == [
            NoteLink(destination: "Projects/Plan%20B.md#goals", kind: .link),
            NoteLink(destination: "_attachments/c.png", kind: .image),
            NoteLink(destination: "https://ci.example.com", kind: .link),
            NoteLink(destination: "b.svg", kind: .image),
            NoteLink(destination: "Other Note.md", kind: .link),
        ])
        #expect(m.firstImage == "_attachments/c.png")
    }

    @Test func pinnedAndCreatedComeFromFrontmatter() {
        let m = meta("---\npinned: yes\ncreated: 2026-01-02\n---\nx")
        #expect(m.pinned)
        #expect(m.created == ISO8601DateFormatter().date(from: "2026-01-02T00:00:00Z"))
        #expect(!meta("x").pinned)
    }

    @Test func searchTextSkipsCodeAndFrontmatter() {
        let m = meta("---\nsecret: x\n---\n# Title\nvisible\n```\nhidden\n```\n")
        #expect(m.searchText == "Title\nvisible")
    }

    @Test func crlfNotesParseTheSame() {
        let m = meta("---\r\ntags: [a]\r\n---\r\n# Title\r\nBody #b\r\n")
        #expect(m.title == "Title")
        #expect(m.tags == ["a", "b"])
        #expect(m.snippet == "Body #b")
    }
}
