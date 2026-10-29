//
//  ExportTests.swift
//  Print / PDF export: the page built from a note, and a real PDF of demo notes.
//

import AppKit
import Foundation
import PDFKit
import Testing
@testable import NmwCore
@testable import NmwUI

@MainActor
@Suite("Print and PDF export")
struct ExportTests {
    init() { EditorSetup.highlightsCode = false }

    private func tempNotebook(_ files: [String: Data]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "nmw-export-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        for (path, data) in files {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        return root
    }

    private func png(_ size: Int) throws -> Data {
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                                samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    @Test func pageEmbedsRelativeImagesAndThemeCSS() throws {
        let root = try tempNotebook(["Trips/.attachments/tram.png": try png(40)])
        defer { try? FileManager.default.removeItem(at: root) }
        let context = NoteContext(noteURL: root.appending(path: "Trips/Lisbon.md"), root: root, previews: nil)
        let html = NoteExport.document(markdown: "---\npinned: true\n---\n# Lisbon\n![](.attachments/tram.png){.small}\n![](missing.png)\n",
                                       title: "Lisbon", context: context)
        #expect(html.contains("<title>Lisbon</title>"))
        #expect(html.contains("src=\"data:image/png;base64,"))
        #expect(html.contains("max-width:min(100%,160px)"))
        #expect(html.contains("[missing.png]"))
        #expect(html.contains("@page"))
        #expect(!html.contains("pinned: true"))
    }

    @Test func fileNamesAreSafe() {
        #expect(NoteExport.fileName("Trip: Lisbon/Porto", ext: "pdf") == "Trip- Lisbon-Porto.pdf")
        #expect(NoteExport.fileName("  ", ext: "md") == "Note.md")
    }

    /// Renders demo notes to paginated PDFs and their first pages to PNG
    /// (`/tmp/wt-p-shots`, for eyeballing). Skipped without the demo notebook.
    @Test func demoNotesBecomePaginatedPDFs() async throws {
        let demo = URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../../../../../design/demo-notebook").standardized
        guard FileManager.default.fileExists(atPath: demo.path) else { return }
        let shots = URL(filePath: "/tmp/wt-p-shots", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
        for note in ["Projects/Kitchen budget.md", "Travel/Lisbon.md", "Projects/App launch plan.md"] {
            let url = demo.appending(path: note)
            let text = try String(contentsOf: url, encoding: .utf8)
            let context = NoteContext(noteURL: url, root: demo, previews: nil)
            let title = NoteMetadata(markdown: text, fileName: url.deletingPathExtension().lastPathComponent).title
            let exporter = NoteExporter(markdown: text, title: title, context: context)
            let pdfURL = try await exporter.pdfFile()
            let document = try #require(PDFDocument(url: pdfURL))
            #expect(document.pageCount >= 1)
            let page = try #require(document.page(at: 0))
            let bounds = page.bounds(for: .mediaBox)
            #expect(abs(bounds.width - NoteExport.paperSize.width) < 2)
            let text0 = page.string ?? ""
            #expect(text0.contains(title))
            let thumb = page.thumbnail(of: NSSize(width: bounds.width * 1.5, height: bounds.height * 1.5), for: .mediaBox)
            let rep = NSBitmapImageRep(data: thumb.tiffRepresentation!)!
            try rep.representation(using: .png, properties: [:])!
                .write(to: shots.appending(path: url.deletingPathExtension().lastPathComponent + ".png"))
            try? FileManager.default.copyItem(at: pdfURL, to: shots.appending(path: pdfURL.lastPathComponent))
        }
    }
}
