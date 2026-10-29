//
//  ImageCacheTests.swift
//

import AppKit
import Foundation
import Testing
@testable import NmwUI

@Suite("Image cache")
struct ImageCacheTests {
    @Test func largePhotosAreDownsampledButKeepTheirSize() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "nmw-imagecache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4000, pixelsHigh: 3000, bitsPerSample: 8,
                                                samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let url = folder.appending(path: "photo.png")
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)

        let image = try #require(ImageCache().image(at: url, maxPixelSize: 1500))
        #expect(image.size == NSSize(width: 4000, height: 3000))
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(max(cgImage.width, cgImage.height) == 1500)
    }
}
