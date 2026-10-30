//
//  PasteTests.swift
//  NmwUITests
//
//  Pasted images become attachments (macOS paste hook), on private
//  pasteboards so the real clipboard is left alone.
//

#if os(macOS)
import AppKit
import Foundation
import Testing
@testable import NmwCore
@testable import NmwUI

@MainActor
@Suite("Pasting images", .serialized)
struct PasteTests {

    private func pasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("nmw-tests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        return pasteboard
    }

    private static let png: Data = {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }()

    @Test func imageDataIsStoredAsAPastedImage() throws {
        let tmp = try TempFolder()
        defer { tmp.delete() }
        let note = try tmp.write("Idea.md", "")
        var stored: [URL] = []
        let handler = EditorSetup.pasteHandler(for: NoteContext(noteURL: note, root: tmp.url, previews: nil)) { stored = $0 }

        let board = pasteboard()
        defer { board.releaseGlobally() }
        board.setData(Self.png, forType: .png)
        let markdown = try #require(handler(board))
        let name = try #require(stored.first?.lastPathComponent)
        #expect(name.hasPrefix("Pasted image ") && name.hasSuffix(".png"))
        #expect(markdown == "![](.attachments/\(LinkPath.encode(name))){.medium}")
        #expect(try Data(contentsOf: stored[0]) == Self.png)

        // Safari's Copy Image comes with the image's URL as text.
        board.clearContents()
        board.setData(Self.png, forType: .png)
        board.setString("https://example.com/a.png", forType: .string)
        #expect(handler(board)?.hasPrefix("![](.attachments/Pasted%20image%20") == true)
    }

    @Test func textWithAPictureOfItselfAndPlainTextStayText() throws {
        let tmp = try TempFolder()
        defer { tmp.delete() }
        let note = try tmp.write("Idea.md", "")
        let handler = EditorSetup.pasteHandler(for: NoteContext(noteURL: note, root: tmp.url, previews: nil)) { _ in }
        let board = pasteboard()
        defer { board.releaseGlobally() }

        board.setString("Q3\t120", forType: .string)
        board.setData(Self.png, forType: .png)
        #expect(handler(board) == nil)
        board.clearContents()
        board.setString("just text", forType: .string)
        #expect(handler(board) == nil)
        #expect(!tmp.exists(".attachments"))
    }

    @Test func copiedImageFilesKeepTheirNamesOtherFilesAreLeftAlone() throws {
        let tmp = try TempFolder()
        defer { tmp.delete() }
        let note = try tmp.write("Projects/Idea.md", "")
        let photo = try tmp.write("Downloads/My Photo.png", data: Self.png)
        let pdf = try tmp.write("Downloads/Q3.pdf", data: Data([2]))
        let handler = EditorSetup.pasteHandler(for: NoteContext(noteURL: note, root: tmp.url, previews: nil)) { _ in }
        let board = pasteboard()
        defer { board.releaseGlobally() }

        board.writeObjects([photo as NSURL])
        #expect(handler(board) == "![](.attachments/My%20Photo.png){.medium}")
        board.clearContents()
        board.writeObjects([pdf as NSURL])
        #expect(handler(board) == nil)
    }
}
#endif
