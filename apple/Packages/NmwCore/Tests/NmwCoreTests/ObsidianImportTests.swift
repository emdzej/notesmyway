//
//  ObsidianImportTests.swift
//  NmwCoreTests
//
//  The Obsidian importer on a small synthetic vault.
//

import Foundation
import Testing
@testable import NmwCore

@Suite("Obsidian import")
struct ObsidianImportTests {

    /// A vault with notes in folders, an attachments folder and Obsidian's settings.
    private func makeVault(in temp: TempFolder) throws -> URL {
        try temp.write("Vault/.obsidian/app.json", #"{"attachmentFolderPath":"Attachments"}"#)
        try temp.write("Vault/.trash/Old.md", "old")
        try temp.write("Vault/Home.md", """
            ---
            tags: [start]
            related: "[[Ideas]]"
            ---
            # Home

            See [[Ideas]], [[Projects/Garden|the garden]] and [[Garden#Spring plan]].
            Back to [[#Home]]. A block: [[Ideas#^abc123]]. Missing: [[Nowhere]].
            ![[tram.jpg]]
            ![[tram.jpg|300]]
            ![[map.png|Map of the city]]
            ![[Ideas]]
            [[manual.pdf]]
            A [markdown link](Projects/Garden.md#beds) and ![old style](Attachments/tram.jpg).
            `[[not a link]]` and \\[[escaped]]

            ```
            [[in code]]
            ```
            | a | b |
            | - | - |
            | [[Ideas\\|Some ideas]] | x |
            """)
        try temp.write("Vault/Ideas.md", "# Ideas\n\n![[tram.jpg]]\n")
        try temp.write("Vault/Projects/Garden.md", "# Garden\n\nHome is [[Home]]. Image: ![[map.png|200x100]]\n")
        try temp.write("Vault/Attachments/tram.jpg", data: Data([0xFF, 0xD8, 0xFF, 0xE0]))
        try temp.write("Vault/Attachments/map.png", data: Data([0x89, 0x50, 0x4E, 0x47]))
        try temp.write("Vault/Attachments/manual.pdf", data: Data("%PDF".utf8))
        try temp.write("Vault/Attachments/unused.png", data: Data([1, 2, 3]))
        return temp.url.appending(path: "Vault", directoryHint: .isDirectory)
    }

    @Test func scansTheVault() throws {
        let temp = try TempFolder()
        defer { temp.delete() }
        let vault = ObsidianImporter.scan(try makeVault(in: temp))
        #expect(vault.notes == ["Home.md", "Ideas.md", "Projects/Garden.md"])
        #expect(vault.files == ["Attachments/manual.pdf", "Attachments/map.png", "Attachments/tram.jpg", "Attachments/unused.png"])
        #expect(vault.hasSettings)
        let notes = try ["Home.md", "Ideas.md", "Projects/Garden.md"].reduce(0) {
            $0 + (try Data(contentsOf: vault.root.appending(path: $1)).count)
        }
        #expect(vault.size == Int64(notes + 4 + 4 + 4 + 3))
    }

    @Test func convertsLinksAndMovesAttachments() throws {
        let temp = try TempFolder()
        defer { temp.delete() }
        let vault = ObsidianImporter.scan(try makeVault(in: temp))
        let notebook = temp.url.appending(path: "Notebook", directoryHint: .isDirectory)
        let destination = notebook.appending(path: "Obsidian", directoryHint: .isDirectory)
        let report = ObsidianImporter(vault: vault, notebookRoot: notebook).run(into: destination)

        #expect(report.imported == 3)
        #expect(report.attachments == 4)          // tram, map, manual next to Home; map next to Garden (Ideas reuses tram)
        #expect(report.otherFiles == 1)           // unused.png
        #expect(report.unresolvedLinks == 1)      // [[Nowhere]]
        #expect(report.embeddedNotes == 1)
        #expect(report.failures.isEmpty)

        let home = try String(contentsOf: destination.appending(path: "Home.md"), encoding: .utf8)
        #expect(home.contains(#"related: "[[Ideas]]""#))   // frontmatter is left alone
        #expect(home.contains("See [Ideas](Ideas.md), [the garden](Projects/Garden.md) and [Garden › Spring plan](Projects/Garden.md#spring-plan)."))
        #expect(home.contains("Back to [Home](#home). A block: [Ideas](Ideas.md). Missing: [[Nowhere]]."))
        #expect(home.contains("\n![](.attachments/tram.jpg)\n![](.attachments/tram.jpg){width=300}\n![Map of the city](.attachments/map.png)\n[Ideas](Ideas.md)\n[manual.pdf](.attachments/manual.pdf)\n"))
        #expect(home.contains("A [markdown link](Projects/Garden.md#beds) and ![old style](.attachments/tram.jpg)."))
        #expect(home.contains(#"`[[not a link]]` and \[[escaped]]"#))
        #expect(home.contains("```\n[[in code]]\n```"))
        #expect(home.contains("| [Some ideas](Ideas.md) | x |"))

        let ideas = try String(contentsOf: destination.appending(path: "Ideas.md"), encoding: .utf8)
        #expect(ideas == "# Ideas\n\n![](.attachments/tram.jpg)\n")
        let garden = try String(contentsOf: destination.appending(path: "Projects/Garden.md"), encoding: .utf8)
        #expect(garden == "# Garden\n\nHome is [Home](../Home.md). Image: ![](.attachments/map.png){width=200 height=100}\n")

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: destination.appending(path: ".attachments/manual.pdf").path))
        #expect(fm.fileExists(atPath: destination.appending(path: "Projects/.attachments/map.png").path))
        #expect(fm.fileExists(atPath: destination.appending(path: "Attachments/unused.png").path))
        #expect(!fm.fileExists(atPath: destination.appending(path: "Attachments/tram.jpg").path))
        #expect(!fm.fileExists(atPath: destination.appending(path: ".obsidian").path))
        #expect(!fm.fileExists(atPath: destination.appending(path: ".trash").path))
        // The vault isn't changed.
        #expect(try String(contentsOf: vault.root.appending(path: "Ideas.md"), encoding: .utf8) == "# Ideas\n\n![[tram.jpg]]\n")
    }

    @Test func attachmentsFollowTheNotebookLayout() throws {
        let temp = try TempFolder()
        defer { temp.delete() }
        let vault = ObsidianImporter.scan(try makeVault(in: temp))
        let notebook = temp.url.appending(path: "Notebook", directoryHint: .isDirectory)
        var layout = NotebookConfig.Attachments()
        layout.placement = .notebookRoot
        _ = ObsidianImporter(vault: vault, notebookRoot: notebook, layout: layout).run(into: notebook.appending(path: "Obsidian"))
        let garden = try String(contentsOf: notebook.appending(path: "Obsidian/Projects/Garden.md"), encoding: .utf8)
        #expect(garden.contains("![](../../.attachments/Garden/map.png)"))
    }

    @Test func resolvesLikeObsidian() {
        let vault = ObsidianImporter.Vault(root: URL(filePath: "/v"), notes: ["A/Note.md", "B/Note.md", "B/C/Deep.md", "Top.md"],
                                           files: ["A/pic.png", "Z/pic.png"], size: 0, hasSettings: true)
        let index = ObsidianImporter.Index(vault)
        #expect(index.resolve("Note", from: "B/C/Deep.md") == .note("B/Note.md"))     // nearest of two
        #expect(index.resolve("note", from: "A/x.md") == .note("A/Note.md"))           // case doesn't matter
        #expect(index.resolve("A/Note", from: "B/C/Deep.md") == .note("A/Note.md"))    // from the root
        #expect(index.resolve("../Note.md", from: "B/C/Deep.md") == .note("B/Note.md")) // relative
        #expect(index.resolve("C/Deep", from: "Top.md") == .note("B/C/Deep.md"))       // partial path
        #expect(index.resolve("pic.png", from: "Z/n.md") == .file("Z/pic.png"))
        #expect(index.resolve("Missing", from: "Top.md") == nil)
        #expect(index.resolve("../../Top", from: "Top.md") == nil)
    }
}
