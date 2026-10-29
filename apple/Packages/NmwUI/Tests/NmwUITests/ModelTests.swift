//
//  ModelTests.swift
//  NmwUITests
//
//  The app's models on real temp folders: editor autosave and conflicts,
//  notebook session lists and file operations (with link fixing), drops,
//  and link classification.
//

import Foundation
import MarkdownEngine
import Testing
@testable import NmwCore
@testable import NmwUI

struct TempFolder {
    let url: URL
    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "nmwui-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
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
        try tmp.write("Projects/Idea.md", "---\npinned: true\n---\n# Idea\n![](../.attachments/Idea/a.png) #project\n")
        try tmp.write(".attachments/Idea/a.png", data: Data([1]))
        try tmp.write(".nmw/config.json", "{}")
        let session = try NotebookSession(notebook: Notebook(root: tmp.url), indexURL: nil, cacheFolder: tmp.url.appending(path: ".nmw/cache"))
        await session.start()
        return (tmp, session)
    }

    @Test func listsScopesAndSearch() async throws {
        let (tmp, s) = try await session()
        defer { s.stop(); tmp.delete() }
        #expect(s.notes.map(\.title) .first == "Idea")                  // pinned first
        #expect(Set(s.notes.map(\.title)) == ["Inbox", "Ann", "Idea"])
        #expect(s.folders.map(\.path.rawValue) == ["People", "Projects"])   // no _attachments, no .nmw
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

        await s.undoLinkFix()
        #expect(try tmp.read("Inbox.md") == "# Inbox\nCall [Ann](People/Ann.md). #todo\n")
        #expect(tmp.exists("People/Ann.md") && !tmp.exists("People/Ann Lee.md"))   // the rename is undone too
        #expect(s.selection == p("People/Ann.md"))
        #expect(editor.url.lastPathComponent == "Ann.md")
        #expect(s.linkFix == nil)
    }

    @Test func movingANoteFixesItsOwnLinksThroughItsEditor() async throws {
        let (tmp, s) = try await session()
        defer { s.stop(); tmp.delete() }
        let editor = s.editor(for: p("Projects/Idea.md"))
        editor.load()
        let moved = try await s.move(p("Projects/Idea.md"), toFolder: nil)
        #expect(moved == p("Idea.md"))
        #expect(editor.text == "---\npinned: true\n---\n# Idea\n![](.attachments/Idea/a.png) #project\n")
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
        #expect(try FileManager.default.contentsOfDirectory(atPath: tmp.url.appending(path: ".nmw/trash").path).count == 1)
        #expect(s.selection == nil)
        #expect(!s.notes.contains { $0.path == p("Inbox.md") })
    }

    @Test func foldersCanBeCreatedRenamedAndTrashed() async throws {
        let (tmp, s) = try await session()
        defer { s.stop(); tmp.delete() }
        let made = try s.createFolder(in: p("Projects"))
        let again = try s.createFolder(in: p("Projects"))
        #expect(made == p("Projects/New Folder") && again == p("Projects/New Folder 2"))
        #expect(s.folders.first { $0.path == p("Projects") }?.children?.count == 2)

        s.scope = .folder(p("People"))
        let renamed = try await s.renameFolder(p("People"), to: "Contacts")
        #expect(renamed == p("Contacts"))
        #expect(s.scope == .folder(p("Contacts")))
        #expect(try tmp.read("Inbox.md") == "# Inbox\nCall [Ann](Contacts/Ann.md). #todo\n")
        #expect(try tmp.read("Contacts/Ann.md") == "# Ann\nSee [the idea](../Projects/Idea.md).\n")   // same depth: unchanged
        #expect(s.linkFix?.move?.to == p("Contacts"))

        try await s.moveFolderToTrash(p("Contacts"))
        #expect(!tmp.exists("Contacts"))
        #expect(s.scope == .folder(nil))
        #expect(!s.notes.contains { $0.path.rawValue.hasPrefix("Contacts/") })
    }

    @Test func attachmentFoldersFollowTheSettings() async throws {
        let (tmp, s) = try await session()
        defer { s.stop(); tmp.delete() }
        try tmp.write("Projects/.attachments/photo.jpg", data: Data([1]))
        try tmp.write("Cars/attachments/scan.pdf", data: Data([1]))
        try tmp.write("Cars/Service.md", "# Service")
        s.refresh()
        func paths(_ nodes: [FolderNode]) -> [String] { nodes.flatMap { [$0.path.rawValue] + paths($0.children ?? []) } }
        // Default: ".attachments", hidden. Other dot folders never show.
        #expect(paths(s.folders) == ["Cars", "Cars/attachments", "People", "Projects"])

        var config = s.config
        config.attachments.folderName = "attachments"
        try s.updateConfig(config)
        #expect(paths(s.folders) == ["Cars", "People", "Projects"])
        config.attachments.showInSidebar = true
        try s.updateConfig(config)
        #expect(paths(s.folders) == ["Cars", "Cars/attachments", "People", "Projects"])
        #expect(NotebookConfig.load(for: s.notebook) == config)   // saved in .nmw/config.json

        config.attachments.folderName = "a/b"
        #expect(throws: (any Error).self) { try s.updateConfig(config) }
    }

    @Test func missingNotesAreCreatedFromTheirLink() async throws {
        let (tmp, s) = try await session()
        defer { s.stop(); tmp.delete() }
        let path = try await s.createMissingNote(at: p("Projects/Next Steps.md"))
        #expect(try tmp.read("Projects/Next Steps.md") == "# Next Steps\n")
        #expect(s.selection == path)
        #expect(try s.index.note(at: path)?.title == "Next Steps")
    }

    @Test func trashOlderThan30DaysIsPurged() async throws {
        let (tmp, s) = try await session()
        defer { s.stop(); tmp.delete() }
        let now = Date()
        let old = Int(now.timeIntervalSince1970) - 31 * 86_400
        let recent = Int(now.timeIntervalSince1970) - 2 * 86_400
        try tmp.write(".nmw/trash/\(old) Old.md", "x")
        try tmp.write(".nmw/trash/\(recent) Recent.md", "y")
        try tmp.write(".nmw/trash/notes.txt", "kept: no timestamp")
        s.purgeTrash(now: now)
        #expect(!tmp.exists(".nmw/trash/\(old) Old.md"))
        #expect(tmp.exists(".nmw/trash/\(recent) Recent.md"))
        #expect(tmp.exists(".nmw/trash/notes.txt"))
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
        #expect(markdown == "![](.attachments/My%20Photo.png){.medium}\n[Q3.pdf](.attachments/Q3.pdf)")
        #expect(stored.count == 2)
        #expect(tmp.exists("Projects/.attachments/My Photo.png"))
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
        let outsideLink = LinkPath.encode(LinkPath.relative(from: note, to: loose))   // ../nmwui-tests-…/loose.md
        #expect(LinkAction.classify(outsideLink, in: context) == .standalone(loose.standardizedFileURL))
        #expect(LinkAction.classify("#top", in: context) == .none)
    }

    @Test func pickerRanksTitlePrefixesFirst() {
        #expect(NotePicker.score("ide", "idea", "projects/idea.md")! > NotePicker.score("ide", "a wide road", "x.md")!)
        #expect(NotePicker.score("xyz", "idea", "projects/idea.md") == nil)
        #expect(NotePicker.score("proj", "idea", "projects/idea.md") != nil)   // path match
    }
}
