//
//  EditorServices.swift
//  NmwUI
//
//  Connects the editor engine to NmwCore for one note: images and preview
//  cards resolve relative to the note, dropped files go to its attachment
//  folder, and clicked links are classified for the app to act on.
//

#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Foundation
import ImageIO
import MarkdownEngine
import MarkdownEngineCodeBlocks
import MarkdownEngineLatex
import NmwCore

/// Where a note lives, for everything the editor resolves against it.
public struct NoteContext: Sendable {
    public let noteURL: URL
    /// Notebook root; nil for standalone files.
    public let root: URL?
    public let previews: LinkPreviewStore?
    /// Where dropped files go (the notebook's settings; defaults for standalone files).
    public let attachments: NotebookConfig.Attachments

    public init(noteURL: URL, root: URL?, previews: LinkPreviewStore?,
                attachments: NotebookConfig.Attachments = NotebookConfig.Attachments()) {
        self.noteURL = noteURL
        self.root = root
        self.previews = previews
        self.attachments = attachments
    }

    func resolve(_ destination: String) -> LinkTarget? {
        LinkTarget.resolve(destination, from: noteURL, root: root)
    }
}

/// Decoded images, keyed by path and modification date.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, PlatformImage>()

    init() { cache.totalCostLimit = 256 * 1024 * 1024 }

    /// The image at `url`, decoded at most `maxPixelSize` pixels on its long
    /// side (photos from a camera are 12 MP+; drawing those while scrolling
    /// stuttered). The image keeps its original size in points, so layout
    /// is unchanged; only its resolution is capped.
    func image(at url: URL, maxPixelSize: Int = 2400) -> PlatformImage? {
        var url = url
        url.removeAllCachedResourceValues()
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
              values.isRegularFile == true else { return nil }
        let key = "\(url.path)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(maxPixelSize)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let (image, cost) = Self.downsampled(url, maxPixelSize: maxPixelSize) ?? Self.original(url) else { return nil }
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }

    private static func downsampled(_ url: URL, maxPixelSize: Int) -> (PlatformImage, Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              var width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              var height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0 else { return nil }
        // EXIF orientations 5–8 rotate by 90°.
        if let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue, orientation >= 5 {
            swap(&width, &height)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxPixelSize, Int(max(width, height))),
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let cost = cgImage.bytesPerRow * cgImage.height
        #if os(macOS)
        return (NSImage(cgImage: cgImage, size: NSSize(width: width, height: height)), cost)
        #else
        // scale < 1 keeps `size` at the original pixel dimensions.
        return (UIImage(cgImage: cgImage, scale: CGFloat(cgImage.width) / width, orientation: .up), cost)
        #endif
    }

    /// Formats ImageIO can't read (e.g. PDF on macOS).
    private static func original(_ url: URL) -> (PlatformImage, Int)? {
        #if os(macOS)
        guard let image = NSImage(contentsOf: url) else { return nil }
        #else
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        #endif
        return (image, Int(image.size.width * image.size.height * 4))
    }
}

/// `![](…)` images: local files relative to the note.
struct NoteImageProvider: ImageProvider {
    let context: NoteContext
    let version: Int

    func image(for request: ImageRequest) -> PlatformImage? {
        guard case .file(let url, _)? = context.resolve(request.source) else { return nil }
        // Enough pixels for the size it's shown at (3x screens), no more.
        let maxPixels = switch request.attributes.size {
        case .icon: 192
        case .small: 900
        case .medium: 1500
        default: 2400
        }
        return ImageCache.shared.image(at: url, maxPixelSize: maxPixels)
    }

    func fingerprint() -> AnyHashable { version }
}

/// `[…](…){.preview}` cards, from the notebook's (or a standalone) preview store.
struct NotePreviewProvider: LinkPreviewProvider {
    let context: NoteContext
    let version: Int

    func preview(for request: LinkPreviewRequest) -> LinkPreview? {
        guard let store = context.previews, let target = context.resolve(request.destination),
              let data = store.preview(for: target) else { return nil }
        let status: LinkPreview.Status = switch data.status {
        case .loading: .loading
        case .ready: .ready
        case .unavailable: .unavailable
        }
        return LinkPreview(status: status, title: data.title, summary: data.summary, subtitle: data.subtitle,
                           icon: data.iconURL.flatMap { ImageCache.shared.image(at: $0, maxPixelSize: 192) },
                           image: data.imageURL.flatMap { ImageCache.shared.image(at: $0, maxPixelSize: 1200) })
    }

    func fingerprint() -> AnyHashable { [version, context.previews?.version ?? 0] }
}

enum EditorSetup {
    /// Off in unit tests: HighlighterSwift loads its themes from a resource
    /// bundle that only the app embeds.
    @MainActor static var highlightsCode = true
    @MainActor static let highlighter: any SyntaxHighlighter = highlightsCode ? HighlighterSwiftBridge() : PlainTextSyntaxHighlighter()
    @MainActor static let latex = SwiftMathBridge()

    /// The engine configuration for a note; `version` changes when images
    /// or previews it may show changed.
    @MainActor
    static func configuration(for context: NoteContext, version: Int, mode: RenderingMode = .formatted) -> MarkdownEditorConfiguration {
        var configuration = MarkdownEditorConfiguration.default
        configuration.renderingMode = mode
        configuration.services.syntaxHighlighter = highlighter
        configuration.services.latex = latex
        configuration.theme.link = Palette.accent
        // Theme, fonts and spacing from Settings › Editor.
        EditorAppearance.shared.apply(to: &configuration, highlightsCode: highlightsCode)
        configuration.services.images = NoteImageProvider(context: context, version: version)
        configuration.services.linkPreviews = NotePreviewProvider(context: context, version: version)
        // No fixed reading width: the detail column is often narrower than one.
        configuration.textInsets = TextInsets(horizontal: 28, vertical: 20)
        return configuration
    }

    /// Stores dropped files with the note and returns their links (spec §4.2):
    /// images as `![](…){.medium}`, other files as `[name](…)`.
    static func dropHandler(for context: NoteContext, stored: @escaping @MainActor ([URL]) -> Void) -> FileDropHandler {
        { files in
            var links: [String] = []
            var urls: [URL] = []
            for file in files {
                guard let attachment = try? AttachmentStore.store(file.url, named: file.name, for: context.noteURL,
                                                                  notebookRoot: context.root, layout: context.attachments) else { continue }
                urls.append(attachment.url)
                let link = file.markdownLink(to: attachment.linkPath)
                links.append(file.isImage ? link + "{.medium}" : link)
            }
            stored(urls)
            return links.isEmpty ? nil : links.joined(separator: "\n")
        }
    }
}

/// What a clicked link means for the app.
public enum LinkAction: Equatable, Sendable {
    /// A note in this notebook.
    case note(NotebookPath)
    /// A markdown file outside the notebook (opens standalone).
    case standalone(URL)
    /// Another local file (open with the system).
    case file(URL)
    /// A web or other URL.
    case external(URL)
    /// A link that leads nowhere (missing file, anchor).
    case none

    static func classify(_ destination: String, in context: NoteContext) -> LinkAction {
        switch context.resolve(destination) {
        case .external(let url)?: return .external(url)
        case .file(let url, _)?:
            let isNote = ["md", "markdown", "mdown", "mkd"].contains(url.pathExtension.lowercased())
            if isNote, let root = context.root, let path = NotebookPath(url: url, root: root) { return .note(path) }
            guard FileManager.default.fileExists(atPath: url.path) else { return .none }
            return isNote ? .standalone(url) : .file(url)
        case .anchor?, nil: return .none
        }
    }
}
