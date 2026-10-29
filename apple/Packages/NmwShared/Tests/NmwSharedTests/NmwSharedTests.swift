//
//  NmwSharedTests.swift
//

import Foundation
import Testing
@testable import NmwShared

@Suite("Shared app/extension data")
struct NmwSharedTests {
    @Test func appLinksRoundTrip() {
        let open = AppLink.open(notebook: "ab12", path: "Projects/My Idea.md")
        #expect(AppLink(url: open.url) == open)
        #expect(open.url.absoluteString.hasPrefix("notesmyway://open?"))
        let new = AppLink.new(notebook: "ab12", folder: nil, text: "# Hi & bye")
        #expect(AppLink(url: new.url) == new)
        #expect(AppLink(url: URL(string: "notesmyway://new")!) == .new())
        #expect(AppLink(url: URL(string: "notesmyway://open?notebook=x")!) == nil)
        #expect(AppLink(url: URL(string: "https://example.com")!) == nil)
    }

    @Test func snapshotRoundTripsAndMerges() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "nmw-snap-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let old = Date(timeIntervalSince1970: 1_000), new = Date(timeIntervalSince1970: 2_000)
        let a = WidgetSnapshot.Note(notebookID: "a", path: "x.md", title: "X", snippet: "", modified: old, pinned: true)
        let b = WidgetSnapshot.Note(notebookID: "b", path: "y.md", title: "Y", snippet: "", modified: new, pinned: true)
        let snapshot = WidgetSnapshot(notebooks: [
            .init(id: "a", name: "A", pinned: [a], recent: [a]),
            .init(id: "b", name: "B", pinned: [b], recent: [b]),
        ], selectedNotebookID: "b")
        try snapshot.save(to: url)
        let loaded = try #require(WidgetSnapshot.load(from: url))
        #expect(loaded.notebooks.count == 2)
        #expect(loaded.allPinned.map(\.title) == ["Y", "X"])
        #expect(loaded.selectedNotebookID == "b")
    }

    @Test func jobsAreListedOnlyOnceCommitted() throws {
        let inbox = FileManager.default.temporaryDirectory.appending(path: "nmw-inbox-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: inbox) }
        let job = ShareJob(notebookID: nil, destination: .inbox, comment: "c", items: [.text("hello"), .url(URL(string: "https://swift.org")!, title: "Swift")])
        let folder = try ShareJob.makeFolder(in: inbox, id: job.id)
        #expect(ShareJob.pending(in: inbox).isEmpty)
        try job.commit(to: folder)
        let pending = ShareJob.pending(in: inbox)
        #expect(pending.count == 1)
        #expect(pending.first?.job == job)
    }
}
