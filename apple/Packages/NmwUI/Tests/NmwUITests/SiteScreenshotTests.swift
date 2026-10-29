//
//  SiteScreenshotTests.swift
//
//  Renders the Mac window offscreen for the website (when the screen is
//  locked and the real window can't be captured). Skipped unless
//  NMW_SITE_SHOT_DIR is set; NMW_SITE_SHOT_NOTEBOOK is the demo notebook
//  (design/demo-notebook) and NMW_SITE_SHOT_NOTE the note to open.
//
//    NMW_SITE_SHOT_DIR=/tmp/shots NMW_SITE_SHOT_NOTEBOOK=…/design/demo-notebook \
//    xcodebuild test -scheme NmwUI -destination 'platform=macOS' -only-testing:NmwUITests/SiteScreenshotTests
//

import AppKit
import Foundation
import SwiftUI
import Testing
import NmwCore
@testable import NmwUI

@Suite("Site screenshots")
@MainActor
struct SiteScreenshotTests {
    private let env = ProcessInfo.processInfo.environment

    @Test func macWindow() async throws {
        guard let out = env["NMW_SITE_SHOT_DIR"], let source = env["NMW_SITE_SHOT_NOTEBOOK"] else { return }
        EditorSetup.highlightsCode = false
        // The sidebar is a glass panel the window server draws; it doesn't render
        // offscreen, so the shot shows the note list and the note (sidebar hidden).
        UserDefaults.standard.set("doubleColumn", forKey: "NmwColumnVisibility")
        defer { UserDefaults.standard.removeObject(forKey: "NmwColumnVisibility") }

        let work = FileManager.default.temporaryDirectory.appending(path: "nmw-siteshot-\(UUID().uuidString)")
        let folder = work.appending(path: "Demo")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        try FileManager.default.copyItem(at: URL(filePath: source), to: folder)

        let defaults = try #require(UserDefaults(suiteName: "nmw-siteshot-\(UUID().uuidString)"))
        let library = Library(defaults: defaults, storage: work.appending(path: "storage"))
        try #require(library.add(folder: folder))
        let session = try #require(library.selectedSession)
        for _ in 0..<100 where session.isIndexing || session.notes.isEmpty { try await Task.sleep(for: .milliseconds(100)) }

        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            session.scope = .all
            session.selection = NotebookPath(env["NMW_SITE_SHOT_NOTE"] ?? "Travel/Lisbon.md")
            let size = NSSize(width: 1280, height: 800)
            let view = NSHostingView(rootView: LibraryView(library: library)
                .tint(Palette.accentColor)
                .frame(width: size.width, height: size.height))
            view.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: view.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.appearance = NSAppearance(named: appearance)
            window.contentView = view
            for _ in 0..<40 { try await Task.sleep(for: .milliseconds(100)); view.layoutSubtreeIfNeeded() }
            let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            let name = appearance == .aqua ? "mac-light" : "mac-dark"
            try #require(rep.representation(using: .png, properties: [:])).write(to: URL(filePath: out).appending(path: name + ".png"))
            window.close()
        }
    }
}
