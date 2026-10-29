//
//  PathAndLinkTests.swift
//  NmyCoreTests
//

import Foundation
import Testing
@testable import NmyCore

@Suite("Notebook paths")
struct NotebookPathTests {

    @Test func normalizes() {
        #expect(NotebookPath("/Projects//./Idea.md")?.rawValue == "Projects/Idea.md")
        #expect(NotebookPath("a/b/../c.md")?.rawValue == "a/c.md")
        #expect(NotebookPath("../outside.md") == nil)
        #expect(NotebookPath("") == nil)
        // NFD "é" (e + combining acute) becomes NFC.
        #expect(NotebookPath("Cafe\u{301}.md")?.rawValue == "Caf\u{E9}.md")
    }

    @Test func parts() {
        let p = path("Projects/Plans/Q3 Plan.md")
        #expect(p.name == "Q3 Plan.md")
        #expect(p.stem == "Q3 Plan")
        #expect(p.pathExtension == "md")
        #expect(p.parent?.rawValue == "Projects/Plans")
        #expect(path("Inbox.md").parent == nil)
    }

    @Test func fromURLs() {
        let root = URL(fileURLWithPath: "/tmp/notebook")
        #expect(NotebookPath(url: URL(fileURLWithPath: "/tmp/notebook/a/b.md"), root: root)?.rawValue == "a/b.md")
        #expect(NotebookPath(url: URL(fileURLWithPath: "/tmp/other/b.md"), root: root) == nil)
        #expect(NotebookPath(url: root, root: root) == nil)
    }
}

@Suite("Link targets")
struct LinkTargetTests {
    let note = URL(fileURLWithPath: "/v/Projects/Idea.md")
    let root = URL(fileURLWithPath: "/v")

    @Test func relativePathsResolveAgainstTheNotesFolder() {
        #expect(LinkTarget.resolve("Plan.md", from: note) == .file(URL(fileURLWithPath: "/v/Projects/Plan.md"), fragment: nil))
        #expect(LinkTarget.resolve("../Guides/Setup%20Guide.md#install", from: note)
                == .file(URL(fileURLWithPath: "/v/Guides/Setup Guide.md"), fragment: "install"))
        #expect(LinkTarget.resolve("<../My Note.md>", from: note) == .file(URL(fileURLWithPath: "/v/My Note.md"), fragment: nil))
    }

    @Test func rootedPathsUseTheNotebookRoot() {
        #expect(LinkTarget.resolve("/Inbox.md", from: note, root: root) == .file(URL(fileURLWithPath: "/v/Inbox.md"), fragment: nil))
    }

    @Test func schemesAndAnchors() {
        #expect(LinkTarget.resolve("https://swift.org", from: note) == .external(URL(string: "https://swift.org")!))
        #expect(LinkTarget.resolve("mailto:a@b.c", from: note) == .external(URL(string: "mailto:a@b.c")!))
        #expect(LinkTarget.resolve("#next-steps", from: note) == .anchor("next-steps"))
        #expect(LinkTarget.resolve("C:notes.md", from: note) != .external(URL(string: "C:notes.md")!))
        #expect(LinkTarget.resolve("  ", from: note) == nil)
    }
}
