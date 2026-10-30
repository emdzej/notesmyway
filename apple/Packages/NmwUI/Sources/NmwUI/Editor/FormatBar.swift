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
        Group {
            if let cell = controller.tableCell {
                TableCellBar(controller: controller, cell: cell)
            } else {
                textBar
            }
        }
        .frame(height: 50)
        .glassEffect(.regular.interactive(), in: Capsule())
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private var textBar: some View {
        HStack(spacing: 0) {
            button("Text Styles", "textformat") { showingStyles = true }
                .popover(isPresented: $showingStyles, attachmentAnchor: .point(.top), arrowEdge: .bottom) {
                    StylePanel(controller: controller)
                        .presentationCompactAdaptation(.popover)
                }
            // Tap: make a checklist; hold: the checklist commands.
            Menu {
                ChecklistCommands(controller: controller)
            } label: {
                icon("checklist")
            } primaryAction: {
                controller.setBlockStyle(.task)
            }
            .accessibilityLabel("Checklist")
            .frame(maxWidth: .infinity)
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

/// While a table cell is edited: its address, formula functions, and bold /
/// italic. Buttons don't take the keyboard, so the cell stays in editing.
private struct TableCellBar: View {
    let controller: MarkdownEditorController
    let cell: MarkdownEditorController.TableCell

    private static let common = ["SUM", "AVERAGE", "MIN", "MAX", "COUNT", "IF"]
    private static let more: [(String, [String])] = [
        ("Math", ["ROUND", "ROUNDUP", "ROUNDDOWN", "ABS", "SQRT", "POWER", "MOD", "INT", "PRODUCT"]),
        ("Conditions", ["COUNTIF", "SUMIF", "AVERAGEIF", "AND", "OR", "NOT", "IFERROR", "COUNTA"]),
        ("Text", ["CONCAT", "LEN", "UPPER", "LOWER", "TRIM", "LEFT", "RIGHT", "MID"]),
    ]

    var body: some View {
        HStack(spacing: 4) {
            Text(cell.address ?? "Header")
                .font(.footnote.monospaced().weight(.semibold))
                .foregroundStyle(Palette.accentColor)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Palette.accentColor.opacity(0.14), in: Capsule())
                .padding(.leading, 8)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    chip("=") { controller.insertInTableCell("=") }
                    ForEach(Self.common, id: \.self) { name in
                        chip(name) { controller.insertFunctionInTableCell(name) }
                    }
                    Menu {
                        ForEach(Self.more, id: \.0) { group, names in
                            Section(group) {
                                ForEach(names, id: \.self) { name in
                                    Button(name) { controller.insertFunctionInTableCell(name) }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "function").font(.system(size: 17)).frame(minWidth: 40, minHeight: 44)
                    }
                    .accessibilityLabel("More Functions")
                    chip(":") { controller.insertInTableCell(":") }
                    chip(",") { controller.insertInTableCell(",") }
                    Divider().frame(height: 24).padding(.horizontal, 4)
                    icon("bold") { controller.toggle(.bold) }
                    icon("italic") { controller.toggle(.italic) }
                }
            }
            icon("keyboard.chevron.compact.down") { controller.endEditing() }
                .padding(.trailing, 4)
        }
        .foregroundStyle(.primary)
    }

    private func chip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.monospaced().weight(.medium))
                .padding(.horizontal, 9).frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func icon(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.system(size: 17)).frame(minWidth: 40, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#endif
