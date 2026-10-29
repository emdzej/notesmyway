//
//  MoveTests.swift
//  NmwCoreTests
//
//  Moves and renames: link rewriting, move detection in the indexer,
//  and the edits that keep links working.
//

import Foundation
import Testing
@testable import NmwCore

@Suite("Link rewriting")
struct LinkRewriterTests {
    let root = URL(fileURLWithPath: "/nb")
    func u(_ p: String) -> URL { root.appending(path: p) }

    @Test func linksFollowAMovedTarget() {
        let text = "Call [Ann](People/Ann%20Lee.md#phone \"title\") or <x> `[Ann](People/Ann%20Lee.md)` [web](https://a.b)"
        let out = LinkRewriter.rewrite(text, from: u("Inbox.md"), to: u("Inbox.md"),
                                       moves: [u("People/Ann Lee.md"): u("Contacts/Ann Lee.md")], root: root)
        #expect(out == "Call [Ann](Contacts/Ann%20Lee.md#phone \"title\") or <x> `[Ann](People/Ann%20Lee.md)` [web](https://a.b)")
    }

    @Test func aMovedNoteKeepsItsOwnRelativeLinks() {
        let text = "![](../_attachments/Idea/sketch.png){.small}\n[see](Plan.md) [home](/Inbox.md) [top](#goal)\n"
        let out = LinkRewriter.rewrite(text, from: u("Projects/Idea.md"), to: u("Archive/2026/Idea.md"),
                                       moves: [u("Projects/Idea.md"): u("Archive/2026/Idea.md")], root: root)
        #expect(out == "![](../../_attachments/Idea/sketch.png){.small}\n[see](../../Projects/Plan.md) [home](/Inbox.md) [top](#goal)\n")
    }

    @Test func rootedLinksStayRootedAndAngledStayAngled() {
        let text = "[a](/People/Ann.md) [b](<People/Ann.md>)\n[ref]: People/Ann.md"
        let out = LinkRewriter.rewrite(text, from: u("Inbox.md"), to: u("Inbox.md"),
                                       moves: [u("People/Ann.md"): u("Team/Ann B.md")], root: root)
        #expect(out == "[a](/Team/Ann%20B.md) [b](<Team/Ann%20B.md>)\n[ref]: Team/Ann%20B.md")
    }

    @Test func nothingToChangeGivesNil() {
        #expect(LinkRewriter.rewrite("[a](b.md)", from: u("x.md"), to: u("y.md"), moves: [:], root: root) == nil)
        #expect(LinkRewriter.rewrite("```\n[a](b.md)\n```", from: u("x.md"), to: u("d/x.md"), moves: [:], root: root) == nil)
    }

    @Test func relativePaths() {
        #expect(LinkPath.relative(from: u("a/b/note.md"), to: u("a/c/x.png")) == "../c/x.png")
        #expect(LinkPath.relative(from: u("note.md"), to: u("note2.md")) == "note2.md")
        #expect(LinkPath.relative(from: u("a/note.md"), to: u("a/b/x.md")) == "b/x.md")
        #expect(LinkPath.encode("My Note (1).md") == "My%20Note%20%281%29.md")
    }
}

@Suite("Moves in the index", .serialized)
struct IndexMoveTests {

    private func fixture() async throws -> (TempFolder, NotebookIndex, NotebookIndexer) {
        let tmp = try TempFolder()
        try tmp.write("Inbox.md", "# Inbox\nCall [Ann](People/Ann%20Lee.md).\n")
        try tmp.write("People/Ann Lee.md", "# Ann Lee\nSee [idea](../Projects/Idea.md).\n")
        try tmp.write("Projects/Idea.md", "# Idea\n![](../_attachments/Idea/a.png)\n")
        try tmp.write("_attachments/Idea/a.png", data: Data([1, 2, 3]))
        let index = try NotebookIndex(notebook: Notebook(root: tmp.url), at: nil)
        let indexer = NotebookIndexer(index: index)
        try await indexer.sync()
        return (tmp, index, indexer)
    }

    private func move(_ tmp: TempFolder, _ from: String, _ to: String) throws {
        let target = tmp.url.appending(path: to)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: tmp.url.appending(path: from), to: target)
    }

    @Test func syncDetectsARename() async throws {
        let (tmp, index, indexer) = try await fixture()
        defer { tmp.delete() }
        try move(tmp, "People/Ann Lee.md", "People/Ann B. Lee.md")
        let changes = try await indexer.sync()
        #expect(changes.moved == [path("People/Ann Lee.md"): path("People/Ann B. Lee.md")])
        #expect(changes.added.isEmpty && changes.removed.isEmpty)

        let edits = try index.linkEdits(for: changes.moved)
        #expect(edits.map(\.path) == [path("Inbox.md")])
        #expect(edits.first?.newText == "# Inbox\nCall [Ann](People/Ann%20B.%20Lee.md).\n")
    }

    @Test func updateDetectsAFolderMove() async throws {
        let (tmp, index, indexer) = try await fixture()
        defer { tmp.delete() }
        try move(tmp, "Projects", "Archive/Projects")
        let changes = try await indexer.update([path("Projects"), path("Archive/Projects")])
        #expect(changes.moved == [path("Projects/Idea.md"): path("Archive/Projects/Idea.md")])

        let edits = try index.linkEdits(for: changes.moved)
        #expect(edits.map(\.path) == [path("Archive/Projects/Idea.md"), path("People/Ann Lee.md")])
        #expect(edits[0].newText == "# Idea\n![](../../_attachments/Idea/a.png)\n")
        #expect(edits[1].newText == "# Ann Lee\nSee [idea](../Archive/Projects/Idea.md).\n")
    }

    @Test func deletingAFolderRemovesWhatWasInIt() async throws {
        let (tmp, index, indexer) = try await fixture()
        defer { tmp.delete() }
        try FileManager.default.removeItem(at: tmp.url.appending(path: "People"))
        let changes = try await indexer.update([path("People")])
        #expect(changes.removed == [path("People/Ann Lee.md")])
        #expect(try index.notes().count == 2)
    }

    @Test func unchangedFilesAreSkipped() async throws {
        let (tmp, _, indexer) = try await fixture()
        defer { tmp.delete() }
        #expect(try await indexer.update([path("Inbox.md"), path("People")]).isEmpty)
    }
}
