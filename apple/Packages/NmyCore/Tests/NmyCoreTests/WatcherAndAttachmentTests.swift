//
//  WatcherAndAttachmentTests.swift
//  NmyCoreTests
//

import Foundation
import Synchronization
import Testing
@testable import NmyCore

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

    @Test func storesUnderTheNotebookAndNumbersClashes() throws {
        let tmp = try TempFolder()
        defer { tmp.delete() }
        let note = tmp.url.appending(path: "Projects/Idea.md")
        let a = try tmp.write("Downloads/photo.jpg", data: Data([1]))
        let b = try tmp.write("Desktop/photo.jpg", data: Data([2]))

        let first = try AttachmentStore.store(a, for: note, notebookRoot: tmp.url)
        #expect(first.url.path.hasSuffix("_attachments/Idea/photo.jpg"))
        #expect(first.linkPath == "../_attachments/Idea/photo.jpg")
        #expect(!first.reused)

        let second = try AttachmentStore.store(b, for: note, notebookRoot: tmp.url)
        #expect(second.linkPath == "../_attachments/Idea/photo 2.jpg")
        #expect(try Data(contentsOf: second.url) == Data([2]))

        // The same file again is reused, not copied a third time.
        let again = try AttachmentStore.store(a, for: note, notebookRoot: tmp.url)
        #expect(again.reused && again.url == first.url)
        #expect(try FileManager.default.contentsOfDirectory(atPath: first.url.deletingLastPathComponent().path).count == 2)
    }

    @Test func standaloneFilesKeepAttachmentsNextToThem() throws {
        let tmp = try TempFolder()
        defer { tmp.delete() }
        let note = tmp.url.appending(path: "Downloads/readme.md")
        let file = try tmp.write("Desktop/Q3 (final).pdf", data: Data([9]))
        let stored = try AttachmentStore.store(file, named: ".Q3 (final).pdf", for: note, notebookRoot: nil)
        #expect(stored.linkPath == "_attachments/readme/Q3 (final).pdf")
        #expect(LinkPath.encode(stored.linkPath) == "_attachments/readme/Q3%20%28final%29.pdf")
        #expect(AttachmentStore.numbered("archive.tar.gz", 3) == "archive.tar 3.gz")
    }
}
