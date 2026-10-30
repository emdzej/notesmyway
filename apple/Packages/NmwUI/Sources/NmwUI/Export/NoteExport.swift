//
//  NoteExport.swift
//  NmwUI
//
//  Print, PDF and Share for a note. The note is rendered to HTML by the
//  engine (`MarkdownHTML`, the same parse the editor uses), styled with the
//  editor theme's light palette, and loaded into an offscreen web view, which
//  prints and paginates it. Images and preview-card icons are embedded as
//  data, so the page needs no file access and the PDF travels on its own.
//

#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Foundation
import ImageIO
import SwiftUI
import MarkdownEngine
import NmwCore
import UniformTypeIdentifiers
import WebKit

#if os(macOS)
typealias ShareAnchorView = NSView
#else
typealias ShareAnchorView = UIView
#endif

// MARK: - HTML page

@MainActor
enum NoteExport {
    nonisolated static let markdownType = UTType("net.daringfireball.markdown") ?? .plainText

    /// The whole page: theme CSS and the note's body.
    static func document(markdown: String, title: String, context: NoteContext, highlightsCode: Bool = EditorSetup.highlightsCode) -> String {
        let appearance = EditorAppearance.shared
        let options = MarkdownHTML.Options(
            resolveImage: { imageSource($0, context: context, maxPixels: 2000) },
            preview: { card(for: $0, context: context) },
            highlighter: highlightsCode && !isDarkAppearance ? EditorSetup.highlighter : nil,
            latex: EditorSetup.latex,
            theme: latexTheme(appearance.theme),
            bodyFontSize: 12
        )
        let body = MarkdownHTML.body(for: markdown, options: options)
        return """
        <!doctype html>
        <html><head><meta charset="utf-8"><title>\(MarkdownHTML.escape(title))</title>
        <style>\(css(theme: appearance.theme, font: appearance.font))</style></head>
        <body><article>\(body)</article></body></html>
        """
    }

    /// Dark mode would color code for a dark page; print is always light.
    private static var isDarkAppearance: Bool {
        #if os(macOS)
        NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        #else
        UITraitCollection.current.userInterfaceStyle == .dark
        #endif
    }

    private static func latexTheme(_ theme: EditorTheme) -> MarkdownEditorTheme {
        var engine = MarkdownEditorTheme.default
        engine.bodyText = EditorTheme.parse(theme.light.text ?? "#1D1D1F") ?? .black
        return engine
    }

    // MARK: Images

    /// A data URI for an image destination (resolved from the note), downsampled.
    static func imageSource(_ destination: String, context: NoteContext, maxPixels: Int) -> String? {
        guard case .file(let url, _)? = context.resolve(destination) else { return nil }
        return dataURI(for: url, maxPixels: maxPixels)
    }

    static func dataURI(for url: URL, maxPixels: Int) -> String? {
        guard let image = ImageCache.shared.image(at: url, maxPixelSize: maxPixels), let cgImage = cgImage(image) else { return nil }
        let opaque = cgImage.alphaInfo == .none || cgImage.alphaInfo == .noneSkipLast || cgImage.alphaInfo == .noneSkipFirst
        let type: UTType = opaque ? .jpeg : .png
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return "data:\(type.preferredMIMEType ?? "image/png");base64,\((data as Data).base64EncodedString())"
    }

    private static func cgImage(_ image: PlatformImage) -> CGImage? {
        #if os(macOS)
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        image.cgImage
        #endif
    }

    private static func card(for destination: String, context: NoteContext) -> MarkdownHTML.LinkCard? {
        guard let store = context.previews, let target = context.resolve(destination),
              let data = store.preview(for: target), data.status == .ready else { return nil }
        return MarkdownHTML.LinkCard(
            title: data.title ?? destination, summary: data.summary, subtitle: data.subtitle,
            iconSource: data.iconURL.flatMap { dataURI(for: $0, maxPixels: 96) },
            imageSource: data.imageURL.flatMap { dataURI(for: $0, maxPixels: 900) }
        )
    }

    // MARK: Style

    static func css(theme: EditorTheme, font: EditorAppearance.Font) -> String {
        let c = theme.light
        let text = c.text ?? "#1D1D1F"
        let muted = c.mutedText ?? "#6E6E73"
        let link = c.link ?? "#1A8FA8"
        let heading = c.heading ?? text
        let codeBackground = c.codeBackground ?? "#F4F4F6"
        let rule = c.rule ?? "#D9D9DE"
        let border = c.tableBorder ?? "#C9C9CF"
        let header = c.tableHeader ?? link + "1F"
        let chip = c.chip ?? "#EEEEF1"
        let tag = c.tag ?? link
        let cardBackground = c.cardBackground ?? "#FAFAFB"
        let cardBorder = c.cardBorder ?? border
        let quote = c.quoteBar ?? rule
        let quoteText = c.quoteText ?? muted
        let bodyFont = fontFamily(font == .theme ? (theme.font ?? "system") : font.rawValue)
        let headingFont = font == .theme ? fontFamily(theme.headingFont ?? theme.font ?? "system") : bodyFont
        return """
        @page { margin: 18mm 16mm; }
        html { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
        body { margin: 0; font: 11.5pt/1.5 \(bodyFont); color: \(text); background: #fff; -webkit-text-size-adjust: none; }
        article { max-width: 100%; }
        h1, h2, h3, h4, h5, h6 { font-family: \(headingFont); color: \(heading); line-height: 1.25; margin: 1.1em 0 .45em; break-after: avoid; }
        h1 { font-size: 1.9em; } h2 { font-size: 1.45em; } h3 { font-size: 1.2em; } h4, h5, h6 { font-size: 1em; }
        article > h1:first-child, .nmw-properties + h1 { margin-top: .2em; }
        p { margin: .5em 0; orphans: 3; widows: 3; }
        a, .nmw-link { color: \(link); text-decoration: underline; text-decoration-thickness: .06em; }
        code { font: .9em ui-monospace, "SF Mono", Menlo, monospace; background: \(codeBackground); padding: .08em .3em; border-radius: 4px; }
        pre.nmw-code { background: \(codeBackground); padding: .8em 1em; border-radius: 8px; white-space: pre-wrap; break-inside: avoid; }
        pre.nmw-code code { background: none; padding: 0; font-size: .85em; }
        blockquote { margin: .6em 0; padding: .1em 0 .1em 1em; border-left: 3px solid \(quote); color: \(quoteText); }
        hr { border: 0; border-top: 1px solid \(rule); margin: 1.2em 0; }
        ul, ol { padding-left: 1.6em; margin: .4em 0; }
        li { margin: .15em 0; }
        ul.nmw-tasks { list-style: none; padding-left: .3em; }
        li.nmw-task { list-style: none; }
        .nmw-box { color: \(link); font-size: 1.1em; margin-right: .2em; }
        li.nmw-done > .nmw-task-text { text-decoration: line-through; color: \(muted); }
        table.nmw-table { border-collapse: collapse; margin: .7em 0; break-inside: avoid; font-size: .95em; }
        .nmw-table th, .nmw-table td { border: 1px solid \(border); padding: .3em .6em; vertical-align: top; }
        .nmw-table th { background: \(header); text-align: left; }
        .nmw-formula { color: \(link); }
        .nmw-error { color: #C0392B; }
        figure.nmw-figure { margin: .8em 0; break-inside: avoid; }
        figure.nmw-center { text-align: center; } figure.nmw-right { text-align: right; }
        img.nmw-image { max-width: 100%; height: auto; border-radius: 6px; }
        img.nmw-inline-image { max-height: 1.2em; vertical-align: -.2em; }
        .nmw-missing { color: \(muted); font-style: italic; }
        .nmw-math { margin: .6em 0; text-align: center; }
        .nmw-properties { margin: 0 0 .8em; }
        .nmw-chip { display: inline-block; background: \(chip); color: \(muted); border-radius: 99px; padding: .1em .65em; font-size: .8em; margin: 0 .25em .25em 0; }
        .nmw-chip.nmw-tag, .nmw-tag { color: \(tag); }
        .nmw-chip.nmw-tag { background: \(tag)1A; }
        .nmw-card { display: flex; gap: .8em; border: 1px solid \(cardBorder); background: \(cardBackground); border-radius: 10px; padding: .7em; margin: .7em 0; max-width: 32em; break-inside: avoid; }
        .nmw-card.nmw-center { margin-left: auto; margin-right: auto; } .nmw-card.nmw-right { margin-left: auto; }
        .nmw-card-image { width: 7em; height: 5em; object-fit: cover; border-radius: 6px; }
        .nmw-card-icon { width: 1.1em; height: 1.1em; vertical-align: -.15em; margin-right: .35em; border-radius: 3px; float: left; }
        .nmw-card-title { font-weight: 600; }
        .nmw-card-summary { color: \(muted); font-size: .9em; margin-top: .2em; }
        .nmw-card-subtitle { color: \(muted); font-size: .8em; margin-top: .25em; }
        """
    }

    private static func fontFamily(_ name: String) -> String {
        switch name.lowercased() {
        case "serif": #""New York", ui-serif, Georgia, serif"#
        case "mono", "monospace", "monospaced": #"ui-monospace, "SF Mono", Menlo, monospace"#
        case "rounded": #"ui-rounded, "SF Pro Rounded", -apple-system, sans-serif"#
        case "system", "sans", "sans-serif", "theme": #"-apple-system, "SF Pro Text", "Helvetica Neue", sans-serif"#
        default: "\"\(name)\", -apple-system, sans-serif"
        }
    }

    /// A safe file name for "Title.pdf".
    static func fileName(_ title: String, ext: String) -> String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|")).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned.isEmpty ? "Note" : String(cleaned.prefix(120))) + "." + ext
    }

    /// Letter in the US, Canada and Mexico; A4 elsewhere.
    static var paperSize: CGSize {
        let region = Locale.current.region?.identifier ?? ""
        return ["US", "CA", "MX", "PH", "CL", "CO", "VE"].contains(region) ? CGSize(width: 612, height: 792) : CGSize(width: 595.28, height: 841.89)
    }
}

// MARK: - Offscreen web view

/// Loads a page and prints / paginates it.
@MainActor
final class NoteRenderer: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    private var loaded: CheckedContinuation<Void, Never>?
    #if os(macOS)
    /// WebKit prints blank pages from a view outside any window.
    private let window: NSWindow
    #endif

    override init() {
        let size = NoteExport.paperSize
        webView = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: WKWebViewConfiguration())
        #if os(macOS)
        window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        #endif
        super.init()
        webView.navigationDelegate = self
    }

    func load(_ html: String) async {
        await withCheckedContinuation { continuation in
            loaded = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated { finish() }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { finish() }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { finish() }
    }

    private func finish() {
        loaded?.resume()
        loaded = nil
    }

    #if os(iOS)
    var printFormatter: UIPrintFormatter { webView.viewPrintFormatter() }

    /// Paginated PDF (A4 or Letter, 0.75 in margins).
    func pdfData() -> Data {
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(webView.viewPrintFormatter(), startingAtPageAt: 0)
        let paper = CGRect(origin: .zero, size: NoteExport.paperSize)
        renderer.setValue(NSValue(cgRect: paper), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: paper.insetBy(dx: 48, dy: 54)), forKey: "printableRect")
        let pdf = UIGraphicsPDFRenderer(bounds: paper)
        return pdf.pdfData { context in
            renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
            for page in 0..<renderer.numberOfPages {
                context.beginPage()
                renderer.drawPage(at: page, in: context.pdfContextBounds)
            }
        }
    }
    #else
    private func printInfo(saveTo url: URL? = nil) -> NSPrintInfo {
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        for edge in [\NSPrintInfo.leftMargin, \.rightMargin] { info[keyPath: edge] = 46 }
        for edge in [\NSPrintInfo.topMargin, \.bottomMargin] { info[keyPath: edge] = 52 }
        if let url {
            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        }
        return info
    }

    private func operation(_ info: NSPrintInfo) -> NSPrintOperation {
        let op = webView.printOperation(with: info)
        op.view?.frame = NSRect(origin: .zero, size: info.paperSize)
        return op
    }

    /// The print panel, as a sheet on `window`.
    /// Returns when the panel is done, so the caller keeps this renderer
    /// (and the web view being printed) alive until then.
    func print(in parent: NSWindow?) async {
        let op = operation(printInfo())
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        guard let parent else {
            op.run()
            return
        }
        let done = PrintDone()
        _ = await withCheckedContinuation { continuation in
            done.continuation = continuation
            op.runModal(for: parent, delegate: done, didRun: #selector(PrintDone.printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
        }
    }

    /// Writes a paginated PDF to `url`.
    func writePDF(to url: URL) async -> Bool {
        let op = operation(printInfo(saveTo: url))
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        let done = PrintDone()
        return await withCheckedContinuation { continuation in
            done.continuation = continuation
            op.runModal(for: window, delegate: done, didRun: #selector(PrintDone.printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
        }
    }
    #endif
}

#if os(macOS)
private final class PrintDone: NSObject {
    var continuation: CheckedContinuation<Bool, Never>?
    @objc func printOperationDidRun(_ op: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        continuation?.resume(returning: success)
        continuation = nil
    }
}
#endif

// MARK: - Exporter

/// Print, PDF and the share items for one note's current text.
@MainActor
final class NoteExporter {
    let markdown: String
    let title: String
    let context: NoteContext
    private let renderer = NoteRenderer()
    private var isLoaded = false

    init(markdown: String, title: String, context: NoteContext) {
        self.markdown = markdown
        self.title = title
        self.context = context
    }

    private func prepare() async {
        guard !isLoaded else { return }
        await renderer.load(NoteExport.document(markdown: markdown, title: title, context: context))
        isLoaded = true
    }

    /// A fresh temporary folder for exported copies.
    private func exportFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "nmw-export-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// The paginated PDF in a temporary "Title.pdf".
    func pdfFile() async throws -> URL {
        await prepare()
        let url = try exportFolder().appending(path: NoteExport.fileName(title, ext: "pdf"))
        #if os(iOS)
        try renderer.pdfData().write(to: url)
        #else
        guard await renderer.writePDF(to: url) else { throw CocoaError(.fileWriteUnknown) }
        #endif
        return url
    }

    /// A temporary "Title.md" copy (the original stays where it is).
    func markdownFile() throws -> URL {
        let url = try exportFolder().appending(path: NoteExport.fileName(title, ext: "md"))
        try markdown.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// The note as Markdown file, PDF and plain text; on iOS also a print
    /// formatter, so the share sheet offers Print.
    func shareItems() async throws -> [Any] {
        var items: [Any] = [try markdownFile(), try await pdfFile(), MarkdownPlainText.text(of: markdown)]
        #if os(iOS)
        items.append(renderer.printFormatter)
        #endif
        return items
    }

    #if os(iOS)
    /// The system print sheet (⌘P on iPad keyboards).
    func print() async {
        await prepare()
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo.printInfo()
        info.jobName = title
        info.outputType = .general
        controller.printInfo = info
        controller.printFormatter = renderer.printFormatter
        controller.present(animated: true)
    }
    #else
    func print(in window: NSWindow?) async {
        await prepare()
        await renderer.print(in: window)
    }

    /// Asks where to save, then writes the PDF there.
    func exportPDF(in window: NSWindow?) async {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = NoteExport.fileName(title, ext: "pdf")
        panel.canCreateDirectories = true
        let response: NSApplication.ModalResponse
        if let window {
            response = await panel.beginSheetModal(for: window)
        } else {
            response = panel.runModal()
        }
        guard response == .OK, let url = panel.url else { return }
        do {
            let temp = try await pdfFile()
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            try FileManager.default.copyItem(at: temp, to: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
    #endif
}

/// Markdown reduced to readable text (for Messages, Mail bodies, Notes).
enum MarkdownPlainText {
    static func text(of markdown: String) -> String {
        String(Frontmatter.body(of: markdown)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Presenting the share sheet

@MainActor
enum NoteSharing {
    /// Builds the items, then shows the share sheet (iOS) / sharing picker
    /// (macOS) near `anchor`, or the window's toolbar area without one.
    static func share(_ exporter: NoteExporter, anchor: ShareAnchorView? = nil) {
        Task { @MainActor in
            guard let items = try? await exporter.shareItems() else { return }
            present(items, anchor: anchor)
        }
    }

    #if os(iOS)
    static func present(_ items: [Any], anchor: UIView?) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController ?? scene.windows.first?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = sheet.popoverPresentationController {
            if let anchor {
                popover.sourceView = anchor
                popover.sourceRect = anchor.bounds
            } else {
                popover.sourceView = top.view
                popover.sourceRect = CGRect(x: top.view.bounds.maxX - 60, y: top.view.safeAreaInsets.top, width: 1, height: 1)
            }
        }
        top.present(sheet, animated: true)
    }
    #else
    static func present(_ items: [Any], anchor: NSView?) {
        let picker = NSSharingServicePicker(items: items)
        if let anchor {
            picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        } else if let view = NSApp.keyWindow?.contentView {
            let mouse = view.convert(NSApp.keyWindow?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
            picker.show(relativeTo: NSRect(origin: mouse, size: CGSize(width: 1, height: 1)), of: view, preferredEdge: .minY)
        }
    }
    #endif
}

// MARK: - Commands from menus and the palette

extension Notification.Name {
    /// Asks the editor whose controller is the `object` to print / export /
    /// share; `userInfo["action"]` is a `NoteExportAction` raw value.
    static let nmwExportNote = Notification.Name("nmwExportNote")
}

enum NoteExportAction: String {
    case print, exportPDF, share
}

/// The focused note's Print / Export as PDF / Share, for the menu bar.
struct NoteExportCommands: Equatable {
    let noteURL: URL
    let run: (NoteExportAction) -> Void
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.noteURL == rhs.noteURL }
}

#if os(macOS)
/// A note for `ShareLink`: its Markdown file first, then a PDF (rendered
/// only if the destination wants one) and plain text.
struct NoteShareItem: Transferable {
    let title: String
    let makeExporter: @MainActor @Sendable () -> NoteExporter

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: NoteExport.markdownType) { item in
            SentTransferredFile(try await item.makeExporter().markdownFile())
        }
        FileRepresentation(exportedContentType: .pdf) { item in
            SentTransferredFile(try await item.makeExporter().pdfFile())
        }
        ProxyRepresentation { item in await MarkdownPlainText.text(of: item.makeExporter().markdown) }
    }
}
#endif
