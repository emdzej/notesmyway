//
//  FormatBar.swift
//  NmwUI
//
//  iOS: the bar above the keyboard, as in Notes: text styles (Aa),
//  checklist, table, attachments, and hiding the keyboard. Every button
//  edits the markdown source through `MarkdownEditorController`.
//

#if os(iOS)
import MarkdownEngine
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct FormatBar: View {
    let controller: MarkdownEditorController
    /// Stores picked files with the note and returns their links (the drop handler); nil hides the attach button.
    let attach: FileDropHandler?

    @State private var showingStyles = false
    @State private var pickingPhoto: PhotosPickerItem?
    @State private var showingPhotos = false
    @State private var showingFiles = false

    var body: some View {
        HStack(spacing: 0) {
            button("Text Styles", "textformat") { showingStyles = true }
                .popover(isPresented: $showingStyles, attachmentAnchor: .point(.top), arrowEdge: .bottom) {
                    StylePanel(controller: controller)
                        .presentationCompactAdaptation(.popover)
                }
            button("Checklist", "checklist") { controller.setBlockStyle(.task) }
            button("Table", "tablecells") { controller.insertTable() }
            if attach != nil {
                Menu {
                    Button("Photo Library", systemImage: "photo.on.rectangle") { showingPhotos = true }
                    Button("Choose File…", systemImage: "folder") { showingFiles = true }
                } label: {
                    icon("paperclip")
                }
                .accessibilityLabel("Attach")
                .frame(maxWidth: .infinity)
            }
            button("Hide Keyboard", "keyboard.chevron.compact.down") { controller.endEditing() }
        }
        .padding(.horizontal, 6)
        .frame(height: 50)
        .glassEffect(.regular.interactive(), in: Capsule())
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .photosPicker(isPresented: $showingPhotos, selection: $pickingPhoto, matching: .images)
        .onChange(of: pickingPhoto) { _, item in
            if let item { Task { await insertPhoto(item) } }
            pickingPhoto = nil
        }
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { Task { await insertFiles(urls) } }
        }
    }

    private func button(_ title: String, _ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { icon(systemImage) }
            .accessibilityLabel(title)
            .frame(maxWidth: .infinity)
    }

    private func icon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 20))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
    }

    private func insertPhoto(_ item: PhotosPickerItem) async {
        guard let attach, let data = try? await item.loadTransferable(type: Data.self) else { return }
        let type = item.supportedContentTypes.first(where: { $0.conforms(to: .image) }) ?? .jpeg
        let folder = FileManager.default.temporaryDirectory.appending(path: "nmw-photo-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let name = "Photo \(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))).\(type.preferredFilenameExtension ?? "jpg")"
        let url = folder.appending(path: name)
        guard (try? data.write(to: url)) != nil else { return }
        if let links = await attach([DroppedFile(url: url, contentType: type, name: name)]) { insert(links) }
    }

    private func insertFiles(_ urls: [URL]) async {
        guard let attach else { return }
        let accessing = urls.map { $0.startAccessingSecurityScopedResource() }
        defer { for (url, ok) in zip(urls, accessing) where ok { url.stopAccessingSecurityScopedResource() } }
        if let links = await attach(urls.map { DroppedFile(url: $0) }) { insert(links) }
    }

    private func insert(_ links: String) {
        controller.insertText(links, actionName: "Attach")
        controller.focus()
    }
}

/// The Aa panel: paragraph styles, inline styles, lists and indentation.
private struct StylePanel: View {
    let controller: MarkdownEditorController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                style("Title", .title, font: .title3.bold())
                style("Heading", .heading, font: .headline)
                style("Subheading", .subheading, font: .subheadline.bold())
                style("Body", .body, font: .subheadline)
            }
            HStack(spacing: 8) {
                inline("bold", .bold)
                inline("italic", .italic)
                inline("strikethrough", .strikethrough)
                inline("chevron.left.forwardslash.chevron.right", .code)
            }
            HStack(spacing: 8) {
                block("list.bullet", .bullet)
                block("list.number", .numbered)
                block("checklist", .task)
                block("text.quote", .quote)
                tile("decrease.indent", selected: false) { controller.outdent() }
                tile("increase.indent", selected: false) { controller.indent() }
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    private func style(_ title: String, _ style: MarkdownFormatting.BlockStyle, font: Font) -> some View {
        let selected = controller.currentBlockStyle == style
        return Button { controller.setBlockStyle(style) } label: {
            Text(title).font(font).lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 38)
                .foregroundStyle(selected ? Color.white : .primary)
                .background(selected ? Palette.accentColor : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private func inline(_ systemImage: String, _ style: MarkdownFormatting.InlineStyle) -> some View {
        tile(systemImage, selected: false) { controller.toggle(style) }
    }

    private func block(_ systemImage: String, _ style: MarkdownFormatting.BlockStyle) -> some View {
        tile(systemImage, selected: controller.currentBlockStyle == style) { controller.setBlockStyle(style) }
    }

    private func tile(_ systemImage: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 38)
                .foregroundStyle(selected ? Color.white : .primary)
                .background(selected ? Palette.accentColor : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }
}
#endif
