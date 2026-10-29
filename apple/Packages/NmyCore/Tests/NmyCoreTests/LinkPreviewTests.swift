//
//  LinkPreviewTests.swift
//  NmyCoreTests
//
//  Web page metadata parsing and the preview store (web via a stubbed
//  URLSession, notes, files, caching).
//

import Foundation
import Synchronization
import Testing
@testable import NmyCore

@Suite("HTML metadata")
struct HTMLMetadataTests {
    let base = URL(string: "https://www.example.com/blog/post")!

    @Test func openGraphWins() {
        let html = """
            <html><head>
            <title> Fallback  Title </title>
            <meta property="og:title" content="Swift &amp; You">
            <meta name="description" content="plain description">
            <meta property='og:description' content='OG description &#8212; long'>
            <meta property="og:image" content="/img/hero.png">
            <meta property="og:site_name" content="Example">
            <link rel="icon" href="/favicon-16.png" sizes="16x16">
            <link rel="apple-touch-icon" href="https://cdn.example.com/touch.png" sizes="180x180">
            </head><body><meta property="og:title" content="ignored"></body></html>
            """
        let m = HTMLMetadata(html: html, baseURL: base)
        #expect(m.title == "Swift & You")
        #expect(m.summary == "OG description — long")
        #expect(m.siteName == "Example")
        #expect(m.imageURL == URL(string: "https://www.example.com/img/hero.png"))
        #expect(m.iconURL == URL(string: "https://cdn.example.com/touch.png"))
    }

    @Test func fallsBackToTitleDescriptionAndFavicon() {
        let html = "<HEAD><TITLE>Old\n  Page</TITLE><META NAME=description CONTENT=\"Hi\"><base href=\"https://other.org/x/\"></HEAD>"
        let m = HTMLMetadata(html: html, baseURL: base)
        #expect(m.title == "Old Page")
        #expect(m.summary == "Hi")
        #expect(m.imageURL == nil)
        #expect(m.iconURL == URL(string: "https://other.org/favicon.ico"))
    }
}

/// Serves canned responses for a test's URLSession.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    struct Response: Sendable { var status = 200; var mime = "text/html"; var body = Data() }
    static let routes = Mutex<[String: Response]>([:])
    static let requests = Mutex<[String]>([])

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let url = request.url!
        Self.requests.withLock { $0.append(url.absoluteString) }
        guard let route = Self.routes.withLock({ $0[url.absoluteString] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: route.status, httpVersion: nil, headerFields: ["Content-Type": route.mime])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: route.body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite("Link preview store", .serialized)
struct LinkPreviewStoreTests {

    private func page(_ url: String) {
        let html = """
            <head><meta property="og:title" content="Swift Evolution">
            <meta property="og:description" content="Proposals"><meta property="og:image" content="/hero.png">
            <link rel="icon" href="/icon.png" sizes="32x32"></head>
            """
        StubProtocol.routes.withLock {
            $0[url] = .init(body: Data(html.utf8))
            $0["https://swift.example/hero.png"] = .init(mime: "image/png", body: Data([0x89, 0x50]))
            $0["https://swift.example/icon.png"] = .init(mime: "image/png", body: Data([0x89, 0x51]))
        }
    }

    @Test func webPagesLoadThenComeFromTheIndexCache() async throws {
        let tmp = try TempFolder()
        defer { tmp.delete() }
        page("https://swift.example/evolution")
        StubProtocol.requests.withLock { $0 = [] }
        let index = try NotebookIndex(notebook: Notebook(root: tmp.url), at: nil)
        let changed = Mutex(0)
        let store = LinkPreviewStore(cacheFolder: tmp.url.appending(path: ".cache"), index: index,
                                     session: StubProtocol.session(), onChange: { changed.withLock { $0 += 1 } })
        let target = LinkTarget.external(URL(string: "https://swift.example/evolution")!)

        #expect(store.preview(for: target)?.status == .loading)
        await store.idle()
        let ready = try #require(store.preview(for: target))
        #expect(ready.status == .ready)
        #expect(ready.title == "Swift Evolution")
        #expect(ready.summary == "Proposals")
        #expect(ready.subtitle == "swift.example")
        #expect(try Data(contentsOf: #require(ready.imageURL)) == Data([0x89, 0x50]))
        #expect(try Data(contentsOf: #require(ready.iconURL)) == Data([0x89, 0x51]))
        #expect(changed.withLock { $0 } == 1)
        #expect(store.version == 1)

        // A new store (next launch) answers from the index without fetching.
        StubProtocol.requests.withLock { $0 = [] }
        let next = LinkPreviewStore(cacheFolder: tmp.url.appending(path: ".cache"), index: index, session: StubProtocol.session())
        _ = next.preview(for: target)
        await next.idle()
        #expect(next.preview(for: target)?.title == "Swift Evolution")
        #expect(StubProtocol.requests.withLock { $0 }.isEmpty)
    }

    @Test func failuresAreUnavailableAndNetworkCanBeOff() async throws {
        let tmp = try TempFolder()
        defer { tmp.delete() }
        let store = LinkPreviewStore(cacheFolder: tmp.url, index: nil, session: StubProtocol.session())
        let missing = LinkTarget.external(URL(string: "https://nowhere.example/")!)
        _ = store.preview(for: missing)
        await store.idle()
        #expect(store.preview(for: missing)?.status == .unavailable)

        var options = LinkPreviewStore.Options()
        options.allowsNetwork = false
        let offline = LinkPreviewStore(cacheFolder: tmp.url, index: nil, session: StubProtocol.session(), options: options)
        #expect(offline.preview(for: missing) == nil)
        #expect(offline.preview(for: .anchor("x")) == nil)
    }

    @Test func notesAndFilesPreviewFromDisk() async throws {
        let tmp = try TempFolder()
        defer { tmp.delete() }
        let note = try tmp.write("Projects/Idea.md", "# Big Idea\nA café for coffee lovers.\n")
        let pdf = try tmp.write("_attachments/Idea/report.pdf", data: Data(repeating: 0, count: 2048))
        let index = try NotebookIndex(notebook: Notebook(root: tmp.url), at: nil)
        try await NotebookIndexer(index: index).sync()
        let store = LinkPreviewStore(cacheFolder: tmp.url.appending(path: ".cache"), index: index)

        let noteTarget = LinkTarget.file(note, fragment: nil)
        let fileTarget = LinkTarget.file(pdf, fragment: nil)
        let goneTarget = LinkTarget.file(tmp.url.appending(path: "Gone.md"), fragment: nil)
        for target in [noteTarget, fileTarget, goneTarget] { _ = store.preview(for: target) }
        await store.idle()

        let notePreview = try #require(store.preview(for: noteTarget))
        #expect(notePreview.title == "Big Idea")
        #expect(notePreview.summary == "A café for coffee lovers.")
        let filePreview = try #require(store.preview(for: fileTarget))
        #expect(filePreview.title == "report.pdf")
        #expect(filePreview.subtitle?.hasSuffix("2 KB") == true)
        #expect(store.preview(for: goneTarget)?.status == .unavailable)

        // Editing the note invalidates its preview.
        try tmp.write("Projects/Idea.md", "# Bigger Idea\nNew text that is longer.\n")
        try await NotebookIndexer(index: index).sync()
        _ = store.preview(for: noteTarget)
        await store.idle()
        #expect(store.preview(for: noteTarget)?.title == "Bigger Idea")
    }

    @Test func standaloneNotesPreviewWithoutAnIndex() async throws {
        let tmp = try TempFolder()
        defer { tmp.delete() }
        let note = try tmp.write("loose/other.md", "Just text #tag\n")
        let store = LinkPreviewStore(cacheFolder: tmp.url.appending(path: ".cache"), index: nil)
        let target = LinkTarget.file(note, fragment: nil)
        _ = store.preview(for: target)
        await store.idle()
        #expect(store.preview(for: target)?.title == "other")
        #expect(store.preview(for: target)?.summary == "Just text #tag")
    }
}
