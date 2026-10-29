//
//  TrashAndTransferTests.swift
//  NmwCoreTests
//

import Foundation
import Testing
@testable import NmwCore

@Suite("Trash")
struct TrashTests {
    private func trashed(_ tmp: TempFolder, _ p: String, at date: Date = Date()) throws -> (NotebookTrash, URL) {
        let trash = NotebookTrash(notebook: Notebook(root: tmp.url))
        let target = try trash.prepare(path(p), now: date)
        try FileManager.default.moveItem(at: tmp.url.appending(path: p), to: target)
        return (trash, target)
    }

    @Test func listsItemsWithTheirOriginalPathAndDate() throws {
        let tmp = try TempFolder(); defer { tmp.delete() }
        try tmp.write("Trips - 2026/Lisbon.md", "# Lisbon\n")
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let (trash, _) = try trashed(tmp, "Trips - 2026/Lisbon.md", at: date)
        let item = try #require(trash.items().first)
        // Recorded exactly, although the folder name contains " - ".
        #expect(item.originalPath == path("Trips - 2026/Lisbon.md"))
        #expect(item.deletedAt == date)
        #expect(item.isNote)
        #expect(item.daysLeft(now: date.addingTimeInterval(86_400 * 10)) == 20)
    }

    @Test func olderItemsAreDecodedFromTheirName() throws {
        let tmp = try TempFolder(); defer { tmp.delete() }
        try tmp.write(".nmw/trash/1790000000 Projects - Idea.md", "x")
        let item = try #require(NotebookTrash(notebook: Notebook(root: tmp.url)).items().first)
        #expect(item.originalPath == path("Projects/Idea.md"))
    }

    @Test func restoreRecreatesFoldersAndAvoidsTakenNames() throws {
        let tmp = try TempFolder(); defer { tmp.delete() }
        try tmp.write("A/B/Note.md", "old")
        let (trash, _) = try trashed(tmp, "A/B/Note.md")
        try FileManager.default.removeItem(at: tmp.url.appending(path: "A"))
        let first = try #require(trash.items().first)
        #expect(try trash.restore(first) == path("A/B/Note.md"))
        #expect(trash.items().isEmpty)

        // Trash it again, put a new note in its place, and restore.
        _ = try trashed(tmp, "A/B/Note.md")
        try tmp.write("A/B/Note.md", "new")
        let again = try #require(trash.items().first)
        #expect(try trash.restore(again) == path("A/B/Note 2.md"))
        #expect(try String(contentsOf: tmp.url.appending(path: "A/B/Note 2.md"), encoding: .utf8) == "old")
    }

    @Test func foldersRestoreWithTheirContents() throws {
        let tmp = try TempFolder(); defer { tmp.delete() }
        try tmp.write("Journal/One.md", "1")
        try tmp.write("Journal/Two.md", "2")
        let (trash, _) = try trashed(tmp, "Journal")
        let item = try #require(trash.items().first)
        #expect(item.isFolder)
        try trash.restore(item)
        #expect(FileManager.default.fileExists(atPath: tmp.url.appending(path: "Journal/Two.md").path))
    }

    @Test func deleteEmptyAndPurge() throws {
        let tmp = try TempFolder(); defer { tmp.delete() }
        let now = Date()
        for name in ["a.md", "b.md", "c.md"] { try tmp.write(name, name) }
        let (trash, _) = try trashed(tmp, "a.md", at: now.addingTimeInterval(-86_400 * 40))
        _ = try trashed(tmp, "b.md", at: now)
        _ = try trashed(tmp, "c.md", at: now.addingTimeInterval(-60))
        trash.purge(now: now)
        #expect(trash.items().map(\.name) == ["b.md", "c.md"])
        try trash.delete(try #require(trash.items().first { $0.name == "b.md" }))
        #expect(trash.items().map(\.name) == ["c.md"])
        try trash.empty()
        #expect(trash.items().isEmpty)
    }
}

@Suite("Move to another notebook")
struct TransferTests {
    @Test func movesTheNoteAndItsAttachments() throws {
        let a = try TempFolder(); defer { a.delete() }
        let b = try TempFolder(); defer { b.delete() }
        try a.write("Trips/Lisbon.md", "# Lisbon\n![](.attachments/tram%2028.jpg){.medium}\n[map](.attachments/map.pdf#page=2)\n[other](../Other.md)\n")
        try a.write("Trips/.attachments/tram 28.jpg", "jpg")
        try a.write("Trips/.attachments/map.pdf", "pdf")
        try a.write("Other.md", "x")
        var target = NotebookConfig()
        target.attachments.placement = .notebookRoot
        target.attachments.folderName = "files"

        let result = try NoteTransfer.move(path("Trips/Lisbon.md"), from: Notebook(root: a.url), fromConfig: NotebookConfig(),
                                           to: Notebook(root: b.url), toConfig: target, folder: path("Travel"))
        #expect(result.path == path("Travel/Lisbon.md"))
        #expect(!FileManager.default.fileExists(atPath: a.url.appending(path: "Trips/Lisbon.md").path))
        let text = try String(contentsOf: b.url.appending(path: "Travel/Lisbon.md"), encoding: .utf8)
        #expect(text.contains("![](../files/Lisbon/tram%2028.jpg){.medium}"))
        #expect(text.contains("[map](../files/Lisbon/map.pdf#page=2)"))
        // Links to other notes are left as written.
        #expect(text.contains("[other](../Other.md)"))
        #expect(FileManager.default.fileExists(atPath: b.url.appending(path: "files/Lisbon/tram 28.jpg").path))
        #expect(result.attachments.count == 2)
        // Originals stay (other notes in the folder may use them).
        #expect(FileManager.default.fileExists(atPath: a.url.appending(path: "Trips/.attachments/map.pdf").path))
    }

    @Test func takenNamesAreNumberedAndEditorTextIsUsed() throws {
        let a = try TempFolder(); defer { a.delete() }
        let b = try TempFolder(); defer { b.delete() }
        try a.write("Idea.md", "on disk")
        try b.write("Idea.md", "theirs")
        let result = try NoteTransfer.move(path("Idea.md"), from: Notebook(root: a.url), fromConfig: NotebookConfig(),
                                           to: Notebook(root: b.url), toConfig: NotebookConfig(), text: "unsaved edit")
        #expect(result.path == path("Idea 2.md"))
        #expect(try String(contentsOf: b.url.appending(path: "Idea 2.md"), encoding: .utf8) == "unsaved edit")
        #expect(try String(contentsOf: b.url.appending(path: "Idea.md"), encoding: .utf8) == "theirs")
    }
}

@Suite("File names from titles")
struct NoteTitleTests {
    @Test func stems() {
        #expect(NoteTitle.fileStem(for: "Trip: Lisbon / Porto") == "Trip- Lisbon - Porto")
        #expect(NoteTitle.fileStem(for: "  .hidden  ") == "hidden")
        #expect(NoteTitle.fileStem(for: "") == nil)
        #expect(NoteTitle.fileStem(for: "Untitled 3") == nil)
        #expect(NoteTitle.fileStem(for: String(repeating: "a", count: 200))?.count == 120)
    }

    @Test func firstHeading() {
        #expect(NoteTitle.firstHeading(in: "---\npinned: true\n---\n# Budget\ntext") == "Budget")
        #expect(NoteTitle.firstHeading(in: "just text") == nil)
    }

    @Test func configRoundTrip() throws {
        let tmp = try TempFolder(); defer { tmp.delete() }
        let notebook = Notebook(root: tmp.url)
        var config = NotebookConfig()
        config.renameFilesToTitle = true
        try config.save(for: notebook)
        #expect(NotebookConfig.load(for: notebook).renameFilesToTitle)
    }
}
