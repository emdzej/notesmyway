//
//  NoteFileTests.swift
//  NmwCoreTests
//
//  Reading and saving notes, in a notebook or standalone.
//

import Foundation
import Testing
@testable import NmwCore

@Suite("Note files", .serialized)
struct NoteFileTests {

    @Test func roundTripKeepsBytes() throws {
        let tmp = try TempFolder()
        defer { tmp.delete() }
        let original = "\u{FEFF}# Title\r\nline two\r\n"
        let url = try tmp.write("a.md", original)
        let file = NoteFile(url: url)
        let snapshot = try file.read()
        #expect(snapshot.text == "# Title\r\nline two\r\n")   // the editor never sees the BOM
        #expect(snapshot.hasByteOrderMark)
        try file.write(snapshot.text, replacing: snapshot)
        #expect(try Data(contentsOf: url) == Data(original.utf8))
    }

    @Test func refusesToOverwriteAnExternalChange() throws {
        let tmp = try TempFolder()
        defer { tmp.delete() }
        let url = try tmp.write("a.md", "v1")
        let file = NoteFile(url: url)
        let snapshot = try file.read()
        try "v2 from another app".write(to: url, atomically: true, encoding: .utf8)

        #expect(throws: NoteFile.Error.self) { try file.write("v1 edited", replacing: snapshot) }
        do {
            try file.write("v1 edited", replacing: snapshot)
        } catch NoteFile.Error.changedOnDisk(let current) {
            #expect(current?.text == "v2 from another app")
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == "v2 from another app")

        // After re-reading, saving works and returns the new snapshot.
        let fresh = try file.read()
        let saved = try file.write("merged", replacing: fresh)
        #expect(saved.text == "merged")
        try file.write("again", replacing: saved)
    }

    @Test func nonUTF8FilesAreRejected() throws {
        let tmp = try TempFolder()
        defer { tmp.delete() }
        let url = try tmp.write("latin1.md", data: Data([0x63, 0x61, 0x66, 0xE9]))   // "café" in Latin-1
        #expect(throws: NoteFile.Error.notUTF8) { try NoteFile(url: url).read() }
    }

    @Test func writingCreatesNewFilesAndFolders() throws {
        let tmp = try TempFolder()
        defer { tmp.delete() }
        let url = tmp.url.appending(path: "New/Untitled.md")
        try NoteFile(url: url).write("# New\n", replacing: nil)
        #expect(try String(contentsOf: url, encoding: .utf8) == "# New\n")
    }

    @Test func standaloneFilesWorkWithoutANotebook() throws {
        let tmp = try TempFolder()
        defer { tmp.delete() }
        let url = try tmp.write("Downloads/readme.md", "# Readme\nSee [guide](docs/Guide%201.md) #draft\n")
        #expect(Notebook.root(enclosing: url) == nil)

        let file = NoteFile(url: url)
        let metadata = NoteMetadata(markdown: try file.read().text, fileName: file.fileName)
        #expect(metadata.title == "Readme")
        #expect(metadata.tags == ["draft"])
        let target = LinkTarget.resolve(metadata.links[0].destination, from: url)
        #expect(target == .file(tmp.url.appending(path: "Downloads/docs/Guide 1.md").standardizedFileURL, fragment: nil))
    }

    @Test func filesInsideAMarkedFolderFindTheirNotebook() throws {
        let tmp = try TempFolder()
        defer { tmp.delete() }
        try FileManager.default.createDirectory(at: tmp.url.appending(path: "Notes/.obsidian"), withIntermediateDirectories: true)
        let url = try tmp.write("Notes/Projects/Idea.md", "x")
        #expect(Notebook.root(enclosing: url)?.standardizedFileURL == tmp.url.appending(path: "Notes").standardizedFileURL)
    }
}
