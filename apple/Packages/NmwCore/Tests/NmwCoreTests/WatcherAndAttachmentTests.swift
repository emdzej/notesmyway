//
//  WatcherAndAttachmentTests.swift
//  NmwCoreTests
//

import Foundation
import Synchronization
import Testing
@testable import NmwCore

#if os(macOS)
@Suite("Notebook watcher (FSEvents)", .serialized)
struct NotebookWatcherTests {

    /// Collects every batch from one long-lived consumer; cancelling the task
    /// that iterates an AsyncStream would end the stream (and the watcher).
    final class Collector: Sendable {
        final class Buffer: Sendable { let batches = Mutex<[IndexChanges]>([]) }
        let buffer = Buffer()
        let task: Task<Void, Never>
        init(_ stream: AsyncStream<IndexChanges>) {
            let buffer = buffer
            task = Task { for await changes in stream { buffer.batches.withLock { $0.append(changes) } } }
        }
        /// The first batch matching `condition`, waiting up to `timeout`.
        func next(timeout: Duration = .seconds(5), where condition: (IndexChanges) -> Bool) async -> IndexChanges? {
            let deadline = ContinuousClock.now + timeout
            while ContinuousClock.now < deadline {
                if let hit = buffer.batches.withLock({ $0.first(where: condition) }) { return hit }
                try? await Task.sleep(for: .milliseconds(50))
            }
            return nil
        }
    }

    @Test func externalWritesAndRenamesReachTheIndex() async throws {
        let tmp = try TempFolder()
        defer { tmp.delete() }
        try tmp.write("Inbox.md", "# Inbox\n")
        let index = try NotebookIndex(notebook: Notebook(root: tmp.url), at: nil)
        let indexer = NotebookIndexer(index: index)
        try await indexer.sync()

        let events = Collector(NotebookWatcher.changes(of: indexer, latency: 0.1))
        defer { events.task.cancel() }
        try await Task.sleep(for: .milliseconds(300))   // let FSEvents start

        try tmp.write("Projects/New Idea.md", "# New Idea\n")   // as vim or git would: no coordination
        let added = await events.next { $0.added.contains(path("Projects/New Idea.md")) }
        #expect(added != nil)
        #expect(try index.note(at: path("Projects/New Idea.md"))?.title == "New Idea")

        try FileManager.default.moveItem(at: tmp.url.appending(path: "Projects/New Idea.md"),
                                         to: tmp.url.appending(path: "Projects/Idea.md"))
        let moved = await events.next { !$0.moved.isEmpty }
        #expect(moved?.moved == [path("Projects/New Idea.md"): path("Projects/Idea.md")])

        try FileManager.default.createDirectory(at: tmp.url.appending(path: ".git"), withIntermediateDirectories: true)
        try tmp.write(".git/HEAD", "ref")
        try tmp.write("Inbox.md", "# Inbox\nupdated\n")
        let updated = await events.next { !$0.updated.isEmpty }
        #expect(updated?.updated == [path("Inbox.md")])   // hidden folders never show up
    }
}
#endif

@Suite("Attachment store", .serialized)
struct AttachmentStoreTests {

    @Test func defaultsToADotFolderNextToTheNoteAndNumbersClashes() throws {
        let tmp = try TempFolder()
        defer { tmp.delete() }
        let note = tmp.url.appending(path: "Projects/Idea.md")
        let a = try tmp.write("Downloads/photo.jpg", data: Data([1]))
        let b = try tmp.write("Desktop/photo.jpg", data: Data([2]))

        let first = try AttachmentStore.store(a, for: note, notebookRoot: tmp.url)
        #expect(first.url.path.hasSuffix("Projects/.attachments/photo.jpg"))
        #expect(first.linkPath == ".attachments/photo.jpg")
        #expect(!first.reused)

        let second = try AttachmentStore.store(b, for: note, notebookRoot: tmp.url)
        #expect(second.linkPath == ".attachments/photo 2.jpg")
        #expect(try Data(contentsOf: second.url) == Data([2]))

        // The same file again is reused, not copied a third time.
        let again = try AttachmentStore.store(a, for: note, notebookRoot: tmp.url)
        #expect(again.reused && again.url == first.url)
        #expect(try FileManager.default.contentsOfDirectory(atPath: first.url.deletingLastPathComponent().path).count == 2)
    }

    @Test func rootPlacementUsesAFolderPerNote() throws {
        let tmp = try TempFolder()
        defer { tmp.delete() }
        let note = tmp.url.appending(path: "Projects/Idea.md")
        let file = try tmp.write("Downloads/scan.pdf", data: Data([1]))
        let layout = NotebookConfig.Attachments(folderName: "attachments", placement: .notebookRoot)
        let stored = try AttachmentStore.store(file, for: note, notebookRoot: tmp.url, layout: layout)
        #expect(stored.linkPath == "../attachments/Idea/scan.pdf")
    }

    @Test func standaloneFilesKeepAttachmentsNextToThem() throws {
        let tmp = try TempFolder()
        defer { tmp.delete() }
        let note = tmp.url.appending(path: "Downloads/readme.md")
        let file = try tmp.write("Desktop/Q3 (final).pdf", data: Data([9]))
        let layout = NotebookConfig.Attachments(placement: .notebookRoot)   // no notebook: next to the file anyway
        let stored = try AttachmentStore.store(file, named: ".Q3 (final).pdf", for: note, notebookRoot: nil, layout: layout)
        #expect(stored.linkPath == ".attachments/Q3 (final).pdf")
        #expect(LinkPath.encode(stored.linkPath) == ".attachments/Q3%20%28final%29.pdf")
        #expect(AttachmentStore.numbered("archive.tar.gz", 3) == "archive.tar 3.gz")
    }
}

@Suite("Notebook config", .serialized)
struct NotebookConfigTests {

    @Test func defaultsRoundTripAndUnknownKeysSurvive() throws {
        let tmp = try TempFolder()
        defer { tmp.delete() }
        let notebook = Notebook(root: tmp.url)
        #expect(NotebookConfig.load(for: notebook) == NotebookConfig())
        try tmp.write(".nmw/config.json", #"{"future": {"x": 1}, "attachments": {"folderName": "files", "placement": "bogus"}}"#)
        var config = NotebookConfig.load(for: notebook)
        #expect(config.attachments.folderName == "files")
        #expect(config.attachments.placement == .nextToNote)   // unknown value: default
        config.attachments.placement = .notebookRoot
        config.attachments.showInSidebar = true
        config.webPreviews = false
        try config.save(for: notebook)
        #expect(NotebookConfig.load(for: notebook) == config)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: NotebookConfig.url(for: notebook))) as? [String: Any]
        #expect((json?["future"] as? [String: Any])?["x"] as? Int == 1)
    }

    @Test func badFolderNamesAreRejected() {
        for bad in ["", " ", ".", "..", "a/b", "a:b"] { #expect(!NotebookConfig.Attachments.isValidFolderName(bad)) }
        for good in [".attachments", "attachments", "_files", "Pliki"] { #expect(NotebookConfig.Attachments.isValidFolderName(good)) }
    }
}
