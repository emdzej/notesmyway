//
//  FeatureTests.swift
//  NmwUITests
//
//  Recently Deleted (restore, delete, empty), Move to Notebook…, renaming
//  files after their first heading, and the command palette's ranking.
//

import Foundation
import Testing
@testable import NmwCore
@testable import NmwUI

@MainActor
@Suite("Recently Deleted, Move to Notebook, file names from headings", .serialized)
struct FeatureTests {

    private func session(_ files: [String: String]) async throws -> (TempFolder, NotebookSession) {
        let tmp = try TempFolder()
        for (path, text) in files { try tmp.write(path, text) }
        let session = try NotebookSession(notebook: Notebook(root: tmp.url), indexURL: nil, cacheFolder: tmp.url.appending(path: ".nmw/cache"))
        await session.start()
        return (tmp, session)
    }

    // MARK: Recently Deleted

    @Test func trashedNotesAndFoldersRestore() async throws {
        let (tmp, s) = try await session(["Projects/Idea.md": "# Idea\n", "Projects/Plan.md": "# Plan\n", "Inbox.md": "# Inbox\n"])
        defer { s.stop(); tmp.delete() }
        try await s.moveToTrash(p("Projects/Idea.md"))
        try await s.moveFolderToTrash(p("Projects"))
        #expect(Set(s.trashItems.map(\.originalPath)) == [p("Projects"), p("Projects/Idea.md")])
        #expect(s.notes.map(\.path) == [p("Inbox.md")])

        // The note's folder is gone: restoring recreates it.
        let note = try #require(s.trashItems.first { $0.originalPath == p("Projects/Idea.md") })
        let restored = try await s.restore(note)
        #expect(restored == p("Projects/Idea.md"))
        #expect(s.selection == restored)
        #expect(s.scope == .folder(p("Projects")))
        #expect(try s.index.note(at: restored)?.title == "Idea")

        // The folder now collides with the recreated one: it comes back as "Projects 2".
        let folder = try #require(s.trashItems.first)
        #expect(try await s.restore(folder) == p("Projects 2"))
        #expect(tmp.exists("Projects 2/Plan.md"))
        #expect(try s.index.note(at: p("Projects 2/Plan.md")) != nil)
        #expect(s.trashItems.isEmpty)
    }

    @Test func deleteNowAndEmpty() async throws {
        let (tmp, s) = try await session(["a.md": "a", "b.md": "b", "c.md": "c"])
        defer { s.stop(); tmp.delete() }
        for name in ["a.md", "b.md", "c.md"] { try await s.moveToTrash(p(name)) }
        s.scope = .trash
        #expect(s.notes.isEmpty)
        try s.deleteForever(try #require(s.trashItems.first { $0.name == "b.md" }))
        #expect(Set(s.trashItems.map(\.name)) == ["a.md", "c.md"])
        try s.emptyTrash()
        #expect(s.trashItems.isEmpty)
    }

    // MARK: Move to Notebook

    @Test func notesMoveToAnotherNotebookWithTheirAttachments() async throws {
        let work = try TempFolder()
        defer { work.delete() }
        try work.write("Home/Trips/Lisbon.md", "# Lisbon\n![](.attachments/tram.jpg)\n")
        try work.write("Home/Trips/.attachments/tram.jpg", "jpg")
        try work.write("Home/Index.md", "# Index\n[Lisbon](Trips/Lisbon.md)\n")
        try work.write("Work/Readme.md", "# Readme\n")
        let defaults = try #require(UserDefaults(suiteName: "nmw-tests-\(UUID().uuidString)"))
        let library = Library(defaults: defaults, storage: nil)
        let work2 = try #require(library.add(folder: work.url.appending(path: "Work")))
        let home = try #require(library.add(folder: work.url.appending(path: "Home")))
        let source = try #require(library.session(for: home.id))
        let target = try #require(library.session(for: work2.id))
        #expect(await eventually { !source.isIndexing && source.notes.count == 2 && !target.isIndexing && target.notes.count == 1 })
        defer { library.shutdown() }

        // The note linking to it is what the UI warns about.
        #expect(try source.index.backlinks(to: p("Trips/Lisbon.md")).map(\.path) == [p("Index.md")])

        source.selection = p("Trips/Lisbon.md")
        let editor = source.editor(for: p("Trips/Lisbon.md"))
        editor.load()
        editor.text = "# Lisbon\n![](.attachments/tram.jpg)\nUnsaved line.\n"
        let moved = try await library.move(p("Trips/Lisbon.md"), from: source, toNotebook: work2.id)
        #expect(moved == p("Lisbon.md"))
        #expect(!work.exists("Home/Trips/Lisbon.md"))
        #expect(try work.read("Work/Lisbon.md") == "# Lisbon\n![](.attachments/tram.jpg)\nUnsaved line.\n")
        #expect(work.exists("Work/.attachments/tram.jpg"))
        #expect(source.selection == nil)
        #expect(source.notes.map(\.path) == [p("Index.md")])
        #expect(try target.index.note(at: p("Lisbon.md"))?.title == "Lisbon")
    }

    // MARK: File names from headings

    @Test func filesFollowTheirFirstHeadingWhenEnabled() async throws {
        let (tmp, s) = try await session(["Untitled.md": "", "Taken.md": "# Taken\n", "Inbox.md": "[new](Untitled.md)\n"])
        defer { s.stop(); tmp.delete() }
        var config = s.config
        config.renameFilesToTitle = true
        try s.updateConfig(config)
        s.titleRenameDelay = .milliseconds(50)

        s.selection = p("Untitled.md")
        let editor = s.editor(for: p("Untitled.md"))
        editor.saveDelay = .milliseconds(20)
        editor.load()
        editor.text = "# Trip: Lisbon\nnotes"
        #expect(await eventually { tmp.exists("Trip- Lisbon.md") })
        // The file moves first; selection and link fixing follow.
        #expect(await eventually { s.selection == p("Trip- Lisbon.md") })
        #expect(await eventually { (try? tmp.read("Inbox.md")) == "[new](Trip-%20Lisbon.md)\n" })
        // Same editor (the view keeps its caret).
        #expect(s.editor(for: p("Trip- Lisbon.md")) === editor)

        // A taken name is left alone.
        editor.text = "# Taken\nnotes"
        try await Task.sleep(for: .milliseconds(300))
        #expect(tmp.exists("Trip- Lisbon.md"))

        // Undoing the rename isn't redone for the same heading.
        editor.text = "# Porto\nnotes"
        #expect(await eventually { tmp.exists("Porto.md") && s.linkFix?.move?.to == p("Porto.md") })
        await s.undoLinkFix()
        #expect(await eventually { tmp.exists("Trip- Lisbon.md") })
        editor.text = "# Porto\nmore notes"
        try await Task.sleep(for: .milliseconds(300))
        #expect(tmp.exists("Trip- Lisbon.md") && !tmp.exists("Porto.md"))
    }

    @Test func filesKeepTheirNameWhenDisabled() async throws {
        let (tmp, s) = try await session(["Note.md": "# Note\n"])
        defer { s.stop(); tmp.delete() }
        s.titleRenameDelay = .milliseconds(20)
        let editor = s.editor(for: p("Note.md"))
        editor.saveDelay = .milliseconds(20)
        editor.load()
        editor.text = "# Renamed\n"
        try await Task.sleep(for: .milliseconds(300))
        #expect(tmp.exists("Note.md") && !tmp.exists("Renamed.md"))
    }

    // MARK: Command palette

    @Test func paletteRanksTitlesAndKeywords() {
        let trash = PaletteItem(id: "t", title: "Move to Trash", systemImage: "trash", keywords: "delete remove")
        let theme = PaletteItem(id: "p", title: "Theme: Paper", systemImage: "paintpalette")
        #expect(CommandPalette.score("trash", trash) != nil)
        #expect(CommandPalette.score("delete", trash) != nil)
        #expect(CommandPalette.score("paper", theme)! > (CommandPalette.score("paper", trash) ?? 0))
        #expect(CommandPalette.score("xyz", theme) == nil)
    }
}
