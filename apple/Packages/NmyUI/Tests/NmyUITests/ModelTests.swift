//
//  ModelTests.swift
//  NmyUITests
//
//  The app's models on real temp folders: editor autosave and conflicts,
//  notebook session lists and file operations (with link fixing), drops,
//  and link classification.
//

import Foundation
import MarkdownEngine
import Testing
@testable import NmyCore
@testable import NmyUI

struct TempFolder {
    let url: URL
    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "nmyui-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    @discardableResult
    func write(_ path: String, _ text: String) throws -> URL { try write(path, data: Data(text.utf8)) }
    @discardableResult
    func write(_ path: String, data: Data) throws -> URL {
        let file = url.appending(path: path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file)
        return file
    }
    func read(_ path: String) throws -> String { try String(contentsOf: url.appending(path: path), encoding: .utf8) }
    func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: url.appending(path: path).path) }
    func delete() { try? FileManager.default.removeItem(at: url) }
}

func p(_ s: String) -> NotebookPath { NotebookPath(s)! }

/// Waits for `condition` on the main actor, up to `timeout`.
@MainActor
func eventually(_ timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(30))
    }
    return condition()
}

@MainActor
@Suite("Note editor model", .serialized)
struct NoteEditorModelTests {

    private func model(_ tmp: TempFolder, _ text: String) throws -> NoteEditorModel {
        let model = NoteEditorModel(url: try tmp.write("Note.md", text))
        model.saveDelay = .milliseconds(40)
        model.load()
        return model
    }

    @Test func autosavesShortlyAfterTyping() async throws {
        let tmp = try TempFolder()
        defer { tmp.delete() }
        let model = try model(tmp, "# Note\n")
        var saved = 0
        model.onSaved = { _ in saved += 1 }
        model.text = "# Note\nfirst"
        model.text = "# Note\nfirst line"
        #expect(try tmp.read("Note.md") == "# Note\n")     // not yet
        #expect(await eventually { saved == 1 })
        #expect(try tmp.read("Note.md") == "# Note\nfirst line")
        #expect(!model.isDirty)
    }

    @Test func outsideEditsAreAdoptedWhenNothingIsUnsaved() async throws {
        let tmp = try TempFolder()
        defer { tmp.delete() }
        let model = try model(tmp, "v1")
        try tmp.write("Note.md", "v2 from vim")
        model.diskDidChange()
        #expect(model.text == "v2 from vim")
        #expect(model.conflict == nil)
    }

    @Test func outsideEditsDuringUnsavedChangesConflict() async throws {
        let tmp = try TempFolder()
        defer { tmp.delete() }
        let model = try model(tmp, "v1")
        model.text = "v1 mine"
        try tmp.write("Note.md", "v1 theirs")
        model.diskDidChange()
        #expect(model.conflict?.text == "v1 theirs")
        try? await Task.sleep(for: .milliseconds(100))
        #expect(try tmp.read("Note.md") == "v1 theirs")   // the pending save didn't clobber it

        model.resolveConflict(.keepBoth)
        #expect(try tmp.read("Note.md") == "v1 mine")
        let copies = try FileManager.default.contentsOfDirectory(atPath: tmp.url.path).filter { $0.contains("(conflict ") }
        #expect(copies.count == 1)
        #expect(try tmp.read(copies[0]) == "v1 theirs")
    }

    @Test func useDiskDiscardsMine() async throws {
        let tmp = try TempFolder()
        defer { tmp.delete() }
        let model = try model(tmp, "v1")
        model.text = "mine"
        try tmp.write("Note.md", "theirs")
        model.flush()   // the save itself detects the change
        #expect(model.conflict?.text == "theirs")
        model.resolveConflict(.useDisk)
        #expect(model.text == "theirs")
        #expect(!model.isDirty)
    }

    @Test func ownSavesDontLookLikeOutsideChanges() async throws {
        let tmp = try TempFolder()
        defer { tmp.delete() }
        let model = try model(tmp, "a")
        model.text = "ab"
        model.flush()
        model.text = "abc"          // typed after the save, before the watcher event
        model.diskDidChange()
        #expect(model.text == "abc")
        #expect(model.conflict == nil)
    }

    @Test func nonUTF8FilesAreReadOnly() throws {
        let tmp = try TempFolder()
        defer { tmp.delete() }
        let url = try tmp.write("Latin.md", data: Data([0x63, 0x61, 0x66, 0xE9]))
        let model = NoteEditorModel(url: url)
        model.load()
        #expect(model.errorMessage != nil)
        model.text = "overwrite?"
        model.flush()
        #expect(try Data(contentsOf: url) == Data([0x63, 0x61, 0x66, 0xE9]))
    }
}

@MainActor
@Suite("Notebook session", .serialized)
struct NotebookSessionTests {

    private func session() async throws -> (TempFolder, NotebookSession) {
        let tmp = try TempFolder()
        try tmp.write("Inbox.md", "# Inbox\nCall [Ann](People/Ann.md). #todo\n")
        try tmp.write("People/Ann.md", "# Ann\nSee [the idea](../Projects/Idea.md).\n")
        try tmp.write("Projects/Idea.md", "---\npinned: true\n---\n# Idea\n![](../_attachments/Idea/a.png) #project\n")
        try tmp.write("_attachments/Idea/a.png", data: Data([1]))
        try tmp.write(".nmy/config.json", "{}")
        let session = try NotebookSession(notebook: Notebook(root: tmp.url), indexURL: nil, cacheFolder: tmp.url.appending(path: ".nmy/cache"))
        await session.start()
        return (tmp, session)
    }

    @Test func listsScopesAndSearch() async throws {
        let (tmp, s) = try await session()
        defer { s.stop(); tmp.delete() }
        #expect(s.notes.map(\.title) .first == "Idea")                  // pinned first
        #expect(Set(s.notes.map(\.title)) == ["Inbox", "Ann", "Idea"])
        #expect(s.folders.map(\.path.rawValue) == ["People", "Projects"])   // no _attachments, no .nmy
        #expect(s.tags.map(\.tag) == ["project", "todo"])

        s.scope = .folder(nil)
        #expect(s.notes.map(\.title) == ["Inbox"])
        s.scope = .folder(p("People"))
        #expect(s.notes.map(\.title) == ["Ann"])
        s.scope = .tag("todo")
        #expect(s.notes.map(\.title) == ["Inbox"])
        s.scope = .pinned
        #expect(s.notes.map(\.title) == ["Idea"])
        s.scope = .all
        s.searchText = "idea"
        #expect(Set(s.notes.map(\.title)) == ["Ann", "Idea"])
        s.scope = .folder(p("Projects"))
        #expect(s.notes.map(\.title) == ["Idea"])
    }

    @Test func newNotesGetUniqueNamesAndAreSelected() async throws {
        let (tmp, s) = try await session()
        defer { s.stop(); tmp.delete() }
        let first = try await s.createNote(in: nil)
        let second = try await s.createNote(in: p("People"))
        let third = try await s.createNote(in: nil)
        #expect(first == p("Untitled.md"))
        #expect(second == p("People/Untitled.md"))
        #expect(third == p("Untitled 2.md"))
        #expect(s.selection == third)
        #expect(s.notes.contains { $0.path == third })
    }

    @Test func renameFixesLinksAndCanBeUndone() async throws {
        let (tmp, s) = try await session()
        defer { s.stop(); tmp.delete() }
        s.selection = p("People/Ann.md")
        let editor = s.editor(for: p("People/Ann.md"))
        editor.load()

        let renamed = try await s.rename(p("People/Ann.md"), to: "Ann Lee")
        #expect(renamed == p("People/Ann Lee.md"))
        #expect(tmp.exists("People/Ann Lee.md") && !tmp.exists("People/Ann.md"))
        #expect(try tmp.read("Inbox.md") == "# Inbox\nCall [Ann](People/Ann%20Lee.md). #todo\n")
        #expect(s.linkFix?.notes == [p("Inbox.md")])
        // The open editor and the selection followed the file.
        #expect(s.selection == renamed)
        #expect(editor.url.lastPathComponent == "Ann Lee.md")
        #expect(s.editor(for: renamed) === editor)

        s.undoLinkFix()
        #expect(try tmp.read("Inbox.md") == "# Inbox\nCall [Ann](People/Ann.md). #todo\n")
        #expect(s.linkFix == nil)
    }

    @Test func movingANoteFixesItsOwnLinksThroughItsEditor() async throws {
        let (tmp, s) = try await session()
        defer { s.stop(); tmp.delete() }
        let editor = s.editor(for: p("Projects/Idea.md"))
        editor.load()
        let moved = try await s.move(p("Projects/Idea.md"), toFolder: nil)
        #expect(moved == p("Idea.md"))
        #expect(editor.text == "---\npinned: true\n---\n# Idea\n![](_attachments/Idea/a.png) #project\n")
        #expect(try tmp.read("Idea.md") == editor.text)
        #expect(try tmp.read("People/Ann.md") == "# Ann\nSee [the idea](../Idea.md).\n")
    }

    @Test func pinAndTrash() async throws {
        let (tmp, s) = try await session()
        defer { s.stop(); tmp.delete() }
        try await s.setPinned(p("Inbox.md"), true)
        #expect(try tmp.read("Inbox.md").hasPrefix("---\npinned: true\n---\n# Inbox"))
        #expect(s.notes.filter(\.pinned).count == 2)
        try await s.setPinned(p("Inbox.md"), false)
        #expect(try tmp.read("Inbox.md") == "# Inbox\nCall [Ann](People/Ann.md). #todo\n")

        s.selection = p("Inbox.md")
        try await s.moveToTrash(p("Inbox.md"))
        #expect(!tmp.exists("Inbox.md"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: tmp.url.appending(path: ".nmy/trash").path).count == 1)
        #expect(s.selection == nil)
        #expect(!s.notes.contains { $0.path == p("Inbox.md") })
    }

    #if os(macOS)
    @Test func outsideEditsReachAnOpenEditor() async throws {
        let (tmp, s) = try await session()
        defer { s.stop(); tmp.delete() }
        let editor = s.editor(for: p("Inbox.md"))
        editor.load()
        try await Task.sleep(for: .milliseconds(300))   // FSEvents start
        try tmp.write("Inbox.md", "# Inbox\nEdited in vim.\n")
        #expect(await eventually { editor.text == "# Inbox\nEdited in vim.\n" })
        #expect(await eventually { s.notes.first { $0.path == p("Inbox.md") }?.snippet == "Edited in vim." })
    }
    #endif
}

@MainActor
@Suite("Editor services")
struct EditorServicesTests {

    @Test func dropsAreStoredWithTheNoteAndLinked() async throws {
        let tmp = try TempFolder()
        defer { tmp.delete() }
        let note = try tmp.write("Projects/Idea.md", "")
        let photo = try tmp.write("Downloads/My Photo.png", data: Data([1]))
        let pdf = try tmp.write("Downloads/Q3.pdf", data: Data([2]))
        var stored: [URL] = []
        let handler = EditorSetup.dropHandler(for: NoteContext(noteURL: note, root: tmp.url, previews: nil)) { stored = $0 }
        let markdown = await handler([DroppedFile(url: photo), DroppedFile(url: pdf)])
        #expect(markdown == "![](../_attachments/Idea/My%20Photo.png){.medium}\n[Q3.pdf](../_attachments/Idea/Q3.pdf)")
        #expect(stored.count == 2)
        #expect(tmp.exists("_attachments/Idea/My Photo.png"))
    }

    @Test func linkClicksAreClassified() throws {
        let tmp = try TempFolder()
        defer { tmp.delete() }
        let note = try tmp.write("Inbox.md", "")
        try tmp.write("People/Ann.md", "")
        try tmp.write("_attachments/a.pdf", data: Data([1]))
        let outside = try TempFolder()
        defer { outside.delete() }
        let loose = try outside.write("loose.md", "")
        let context = NoteContext(noteURL: note, root: tmp.url, previews: nil)
        #expect(LinkAction.classify("People/Ann.md", in: context) == .note(p("People/Ann.md")))
        #expect(LinkAction.classify("Missing.md", in: context) == .note(p("Missing.md")))
        #expect(LinkAction.classify("_attachments/a.pdf", in: context) == .file(tmp.url.appending(path: "_attachments/a.pdf").standardizedFileURL))
        #expect(LinkAction.classify("https://swift.org", in: context) == .external(URL(string: "https://swift.org")!))
        let outsideLink = LinkPath.encode(LinkPath.relative(from: note, to: loose))   // ../nmyui-tests-…/loose.md
        #expect(LinkAction.classify(outsideLink, in: context) == .standalone(loose.standardizedFileURL))
        #expect(LinkAction.classify("#top", in: context) == .none)
    }

    @Test func pickerRanksTitlePrefixesFirst() {
        #expect(NoteLinkPicker.score("ide", "idea", "projects/idea.md")! > NoteLinkPicker.score("ide", "a wide road", "x.md")!)
        #expect(NoteLinkPicker.score("xyz", "idea", "projects/idea.md") == nil)
        #expect(NoteLinkPicker.score("proj", "idea", "projects/idea.md") != nil)   // path match
    }
}
