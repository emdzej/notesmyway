//
//  IntegrationTests.swift
//  NmwUITests
//
//  System integration without the system: share-job import, the
//  operations Shortcuts run, app links and Spotlight identifiers.
//

import Foundation
import NmwShared
import Testing
@testable import NmwCore
@testable import NmwUI

@Suite("System integration")
@MainActor
struct IntegrationTests {
    init() { Integration.shared.isEnabled = false }

    private func job(_ items: [ShareJob.Item], destination: ShareJob.Destination, title: String? = nil, comment: String? = nil,
                     images: [String: Data] = [:]) throws -> (ShareJob, ShareJob.Folder, TempFolder) {
        let inbox = try TempFolder()
        let job = ShareJob(notebookID: nil, destination: destination, title: title, comment: comment, items: items)
        let folder = try ShareJob.makeFolder(in: inbox.url, id: job.id)
        for (name, data) in images { try data.write(to: folder.file(name)) }
        try job.commit(to: folder)
        return (job, folder, inbox)
    }

    @Test func sharedContentBecomesANote() throws {
        let notebook = try TempFolder()
        defer { notebook.delete() }
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        let (job, folder, inbox) = try job([
            .url(URL(string: "https://swift.org/blog")!, title: "Swift Blog"),
            .text("Worth reading later."),
            .image(fileName: "photo.png"),
        ], destination: .newNote, comment: "From Safari", images: ["photo.png": png])
        defer { inbox.delete() }

        let path = try ShareImporter.write(job, from: folder, into: Notebook(root: notebook.url))
        #expect(path.rawValue == "Swift Blog.md")
        let text = try notebook.read("Swift Blog.md")
        #expect(text.hasPrefix("# Swift Blog\n\nFrom Safari\n"))
        #expect(text.contains("[Swift Blog](https://swift.org/blog){.preview}"))
        #expect(text.contains("Worth reading later."))
        #expect(text.contains("![](.attachments/photo.png){.medium}"))
        #expect(notebook.exists(".attachments/photo.png"))

        // A second share with the same title gets its own file.
        let again = try ShareImporter.write(job, from: folder, into: Notebook(root: notebook.url))
        #expect(again.rawValue == "Swift Blog 2.md")
    }

    @Test func inboxEntriesAreAppended() throws {
        let notebook = try TempFolder()
        defer { notebook.delete() }
        let (first, folder1, inbox1) = try job([.text("First thought")], destination: .inbox)
        let (second, folder2, inbox2) = try job([.url(URL(string: "https://example.com")!, title: nil)], destination: .inbox, title: "Look")
        defer { inbox1.delete(); inbox2.delete() }

        _ = try ShareImporter.write(first, from: folder1, into: Notebook(root: notebook.url))
        _ = try ShareImporter.write(second, from: folder2, into: Notebook(root: notebook.url))
        let text = try notebook.read("Inbox.md")
        #expect(text.hasPrefix("# Inbox\n"))
        #expect(text.components(separatedBy: "\n## ").count == 3)
        #expect(text.contains("First thought"))
        #expect(text.contains("**Look**"))
        #expect(text.contains("[example.com](https://example.com){.preview}"))
    }

    @Test func suggestedTitles() {
        #expect(ShareImporter.suggestedTitle(for: [.text("Line one\nLine two")]) == "Line one")
        #expect(ShareImporter.suggestedTitle(for: [.url(URL(string: "https://a.b/c")!, title: nil)]) == "a.b")
        #expect(ShareImporter.suggestedTitle(for: [.image(fileName: "x.png")]) == "Shared Image")
    }

    @Test func shortcutsCreateAppendAndRead() async throws {
        let notebook = try TempFolder()
        defer { notebook.delete() }
        try notebook.write("Projects/Plan.md", "# Plan\n")
        let defaults = UserDefaults(suiteName: "nmw-integration-\(UUID().uuidString)")!
        let library = Library(defaults: defaults, storage: nil)
        let entry = try #require(library.add(folder: notebook.url))

        let note = try await library.createNote(notebookID: entry.id, folder: "Projects", title: "Groceries", body: "- milk")
        #expect(note.path == "Projects/Groceries.md")
        #expect(try notebook.read("Projects/Groceries.md") == "# Groceries\n\n- milk\n")

        try await library.append("- bread", toNote: note.id)
        #expect(try library.text(ofNote: note.id) == "# Groceries\n\n- milk\n\n- bread\n")

        #expect(library.searchNotes("bread").map(\.title) == ["Groceries"])
        #expect(library.notes(withIDs: [note.id]).first?.title == "Groceries")
        await #expect(throws: IntegrationError.self) {
            try await library.createNote(notebookID: entry.id, folder: "Missing", title: "X", body: "")
        }
    }

    @Test func appLinksAndSpotlightIdentifiers() async throws {
        let notebook = try TempFolder()
        defer { notebook.delete() }
        try notebook.write("Travel/Lisbon.md", "# Lisbon\n")
        let library = Library(defaults: UserDefaults(suiteName: "nmw-links-\(UUID().uuidString)")!, storage: nil)
        let entry = try #require(library.add(folder: notebook.url))

        let id = SpotlightIndex.identifier(notebookID: entry.id, path: p("Travel/Lisbon.md"))
        #expect(SpotlightIndex.parse(id)?.notebookID == entry.id)
        #expect(SpotlightIndex.parse(id)?.path == p("Travel/Lisbon.md"))

        #expect(library.handle(AppLink.open(notebook: entry.id, path: "Travel/Lisbon.md").url))
        #expect(library.selectedSession?.selection == p("Travel/Lisbon.md"))
        #expect(!library.handle(URL(fileURLWithPath: "/tmp/x.md")))
    }
}
