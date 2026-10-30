//
//  FormatControls.swift
//  NmwUI
//
//  Formatting controls shared by the iOS bar above the keyboard and the
//  Mac's editor toolbar: the Aa panel and the checklist commands.
//

import MarkdownEngine
import SwiftUI

/// Checklist commands, for a menu.
struct ChecklistCommands: View {
    let controller: MarkdownEditorController

    var body: some View {
        Button("Mark as Checked", systemImage: "checkmark.circle") { controller.checklist(.toggleChecked) }
        Button("Check All", systemImage: "checklist.checked") { controller.checklist(.checkAll) }
        Button("Uncheck All", systemImage: "checklist.unchecked") { controller.checklist(.uncheckAll) }
        Button("Move Checked to Bottom", systemImage: "arrow.down.to.line") { controller.checklist(.moveCheckedToBottom) }
        Button("Delete Checked", systemImage: "trash", role: .destructive) { controller.checklist(.deleteChecked) }
    }
}

/// The Aa panel: paragraph styles, inline styles, lists and indentation.
struct StylePanel: View {
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

#if os(macOS)
/// The Mac's formatting buttons in the note's toolbar.
struct MacFormatControls: View {
    let controller: MarkdownEditorController
    let canEdit: Bool
    let attach: FileDropHandler

    @State private var showingStyles = false
    @State private var choosingFiles = false

    var body: some View {
        Button { showingStyles = true } label: { Label("Text Styles", systemImage: "textformat") }
            .help("Text Styles")
            .popover(isPresented: $showingStyles, arrowEdge: .bottom) { StylePanel(controller: controller) }
            .disabled(!canEdit)
        // Click: make a checklist; the arrow: the checklist commands.
        Menu {
            ChecklistCommands(controller: controller)
        } label: {
            Label("Checklist", systemImage: "checklist")
        } primaryAction: {
            controller.setBlockStyle(.task)
        }
        .help("Checklist (⇧⌘L)")
        .disabled(!canEdit)
        Button { controller.insertTable() } label: { Label("Table", systemImage: "tablecells") }
            .help("Insert Table (⌥⌘T)")
            .disabled(!canEdit)
        Button { choosingFiles = true } label: { Label("Attach Files", systemImage: "paperclip") }
            .help("Attach Files")
            .disabled(!canEdit)
            .fileImporter(isPresented: $choosingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                Task { await insert(urls) }
            }
    }

    private func insert(_ urls: [URL]) async {
        let accessing = urls.map { $0.startAccessingSecurityScopedResource() }
        defer { for (url, ok) in zip(urls, accessing) where ok { url.stopAccessingSecurityScopedResource() } }
        if let links = await attach(urls.map { DroppedFile(url: $0) }) {
            controller.insertText(links, actionName: "Attach")
            controller.focus()
        }
    }
}
#endif
