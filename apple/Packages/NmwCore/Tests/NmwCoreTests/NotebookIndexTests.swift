//
//  NotebookIndexTests.swift
//  NmwCoreTests
//
//  Scanning a notebook folder into the index and querying it.
//

import Foundation
import Testing
@testable import NmwCore

@Suite("Notebook index", .serialized)
struct NotebookIndexTests {

    /// A small notebook on disk plus an in-memory index over it.
    struct Fixture {
        let tmp: TempFolder
        let notebook: Notebook
        let index: NotebookIndex
        let indexer: NotebookIndexer

        init() throws {
            tmp = try TempFolder()
            try tmp.write("Inbox.md", "# Inbox\nCall [Ann](People/Ann%20Lee.md). #todo\n")
            try tmp.write("People/Ann Lee.md", "---\ntags: [person]\npinned: true\n---\n# Ann Lee\nWorks on [the idea](../Projects/Idea.md).\n")
            try tmp.write("Projects/Idea.md", "# Big Idea\nA café for #project/coffee lovers.\n![](../_attachments/Idea/sketch.png)\n")
            try tmp.write("_attachments/Idea/sketch.png", data: Data([0x89, 0x50, 0x4E, 0x47]))
            try tmp.write(".obsidian/workspace.json", "{}")
            try tmp.write(".hidden.md", "# Hidden")
            notebook = Notebook(root: tmp.url)
            index = try NotebookIndex(notebook: notebook, at: nil)
            indexer = NotebookIndexer(index: index)
        }
    }

    @Test func scanSkipsHiddenFilesAndClassifies() throws {
        let f = try Fixture()
        defer { f.tmp.delete() }
        let files = try NotebookScanner.scan(f.notebook).sorted { $0.path < $1.path }
        #expect(files.map(\.path.rawValue) == ["_attachments/Idea/sketch.png", "Inbox.md", "People/Ann Lee.md", "Projects/Idea.md"])
        #expect(files.map(\.kind) == [.attachment, .note, .note, .note])
    }

    @Test func syncIndexesThenOnlyRereadsChanges() async throws {
        let f = try Fixture()
        defer { f.tmp.delete() }
        let first = try await f.indexer.sync()
        #expect(first.added.count == 4)
        #expect(try await f.indexer.sync().isEmpty)

        try f.tmp.write("Inbox.md", "# Inbox\nNothing left.\n")
        try FileManager.default.removeItem(at: f.tmp.url.appending(path: "Projects/Idea.md"))
        try f.tmp.write("New.md", "fresh")
        let second = try await f.indexer.sync()
        #expect(second.updated == [path("Inbox.md")])
        #expect(second.removed == [path("Projects/Idea.md")])
        #expect(second.added == [path("New.md")])
        #expect(try f.index.note(at: path("New.md"))?.title == "New")
        #expect(try f.index.search("café").isEmpty)
    }

    @Test func listsNotesPinnedFirstAndByFolder() async throws {
        let f = try Fixture()
        defer { f.tmp.delete() }
        try await f.indexer.sync()
        let all = try f.index.notes(sortedBy: .title)
        #expect(all.map(\.title) == ["Ann Lee", "Big Idea", "Inbox"])
        #expect(all.first?.pinned == true)
        #expect(try f.index.notes(in: nil, recursive: false).map(\.title) == ["Inbox"])
        #expect(try f.index.notes(in: path("Projects")).map(\.title) == ["Big Idea"])
        let idea = try #require(try f.index.note(at: path("Projects/Idea.md")))
        #expect(idea.snippet == "A café for #project/coffee lovers.")
        #expect(idea.firstImage == "../_attachments/Idea/sketch.png")
    }

    @Test func backlinksFollowRelativeAndEncodedPaths() async throws {
        let f = try Fixture()
        defer { f.tmp.delete() }
        try await f.indexer.sync()
        #expect(try f.index.backlinks(to: path("People/Ann Lee.md")).map(\.title) == ["Inbox"])
        #expect(try f.index.backlinks(to: path("Projects/Idea.md")).map(\.title) == ["Ann Lee"])
        #expect(try f.index.backlinks(to: path("_attachments/Idea/sketch.png")).map(\.title) == ["Big Idea"])
    }

    @Test func tagsIncludeNestedOnes() async throws {
        let f = try Fixture()
        defer { f.tmp.delete() }
        try await f.indexer.sync()
        #expect(try f.index.tags() == [
            TagCount(tag: "person", count: 1), TagCount(tag: "project/coffee", count: 1), TagCount(tag: "todo", count: 1),
        ])
        #expect(try f.index.notes(taggedWith: "#Project").map(\.title) == ["Big Idea"])
    }

    @Test func searchMatchesPrefixesAndFilters() async throws {
        let f = try Fixture()
        defer { f.tmp.delete() }
        try await f.indexer.sync()
        #expect(try f.index.search("cafe").map(\.title) == ["Big Idea"])        // diacritics ignored
        #expect(try f.index.search("lov").map(\.title) == ["Big Idea"])         // prefix
        #expect(try f.index.search("ann idea").map(\.title) == ["Ann Lee"])     // all words
        #expect(try f.index.search("tag:person").map(\.title) == ["Ann Lee"])
        #expect(try f.index.search("path:Projects big").map(\.title) == ["Big Idea"])
        #expect(try f.index.search("path:Projects ann").isEmpty)
        #expect(try f.index.search("\"OR\" AND NEAR(").isEmpty)                 // FTS syntax is inert
        #expect(try f.index.search("   ").isEmpty)
    }

    @Test func updateReindexesNamedPaths() async throws {
        let f = try Fixture()
        defer { f.tmp.delete() }
        try await f.indexer.sync()
        try f.tmp.write("Inbox.md", "# Renamed Inbox\n")
        try FileManager.default.removeItem(at: f.tmp.url.appending(path: "Projects/Idea.md"))
        let changes = try await f.indexer.update([path("Inbox.md"), path("Projects/Idea.md"), path("Missing.md")])
        #expect(changes.updated == [path("Inbox.md")])
        #expect(changes.removed == [path("Projects/Idea.md")])
        #expect(try f.index.note(at: path("Inbox.md"))?.title == "Renamed Inbox")
        #expect(try f.index.backlinks(to: path("People/Ann Lee.md")).isEmpty)
    }

    @Test func indexPersistsOnDisk() async throws {
        let f = try Fixture()
        defer { f.tmp.delete() }
        let dbURL = f.tmp.url.appending(path: ".nmw-test-index/index.sqlite")
        try await NotebookIndexer(index: NotebookIndex(notebook: f.notebook, at: dbURL)).sync()
        let reopened = try NotebookIndex(notebook: f.notebook, at: dbURL)
        #expect(try reopened.notes().count == 3)
        #expect(try await NotebookIndexer(index: reopened).sync().isEmpty)
    }
}
