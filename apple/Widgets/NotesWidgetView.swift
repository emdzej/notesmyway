//
//  NotesWidgetView.swift
//  NmwWidgets
//

import NmwShared
import SwiftUI
import WidgetKit

enum WidgetPalette {
    /// The app's accent: `#1A8FA8` light, `#5CCFDB` dark.
    static let accent = Color("AccentColor")
}

struct NotesWidgetView: View {
    let kind: NotesKind
    let entry: NotesEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            if let note = entry.notes.first {
                Label(note.title, systemImage: kind.symbol).widgetURL(note.link)
            } else {
                Label("No notes", systemImage: kind.symbol)
            }
        case .accessoryRectangular:
            accessory
        default:
            list
        }
    }

    private var maxNotes: Int {
        switch family {
        case .systemSmall: 3
        case .systemMedium: 3
        case .systemLarge: 7
        default: 1
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
            HStack(spacing: 5) {
                Image(systemName: kind.symbol).font(.caption.weight(.semibold))
                Text(kind.title).font(.caption.weight(.semibold))
                Spacer(minLength: 4)
                Link(destination: AppLink.new().url) {
                    Image(systemName: "square.and.pencil")
                        .font(.footnote.weight(.semibold))
                        .padding(5)
                        .background(WidgetPalette.accent.opacity(0.15), in: Circle())
                }
                .accessibilityLabel("New Note")
            }
            .foregroundStyle(WidgetPalette.accent)

            if entry.notes.isEmpty {
                Spacer(minLength: 0)
                Text(emptyMessage).font(.footnote).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ForEach(entry.notes.prefix(maxNotes)) { note in
                    Link(destination: note.link) { row(note) }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var emptyMessage: String {
        guard entry.hasNotebooks else { return "Open Notes my Way to add a notebook." }
        return kind == .pinned ? "Pin a note to see it here." : "No notes yet."
    }

    private func row(_ note: WidgetSnapshot.Note) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(note.title).font(.subheadline.weight(.semibold)).lineLimit(1)
            if family != .systemSmall {
                HStack(spacing: 4) {
                    Text(note.modified, style: .date)
                    if !note.snippet.isEmpty { Text(note.snippet).foregroundStyle(.secondary) }
                }
                .font(.caption)
                .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessory: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(kind.title, systemImage: kind.symbol).font(.caption2.weight(.semibold))
            if let note = entry.notes.first {
                Text(note.title).font(.headline).lineLimit(1)
                Text(note.snippet).font(.caption).lineLimit(1).foregroundStyle(.secondary)
            } else {
                Text(emptyMessage).font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(entry.notes.first?.link)
    }
}

/// A faint page-with-# watermark in the corner, as in the app.
struct WidgetBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                Color("WidgetBackground")
                PageMark()
                    .stroke(WidgetPalette.accent.opacity(colorScheme == .dark ? 0.14 : 0.10),
                            style: StrokeStyle(lineWidth: max(1.5, side * 0.02), lineCap: .round, lineJoin: .round))
                    .frame(width: side * 0.55, height: side * 0.7)
                    .position(x: proxy.size.width - side * 0.12, y: proxy.size.height - side * 0.08)
            }
        }
    }
}

/// The icon's page: a sheet with a folded top-right corner and a `#`.
struct PageMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let fold = rect.width * 0.28
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        path.move(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY + fold))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
        // #
        let h = CGRect(x: rect.minX + rect.width * 0.22, y: rect.minY + rect.height * 0.38, width: rect.width * 0.5, height: rect.height * 0.36)
        for x in [h.minX + h.width * 0.35, h.minX + h.width * 0.7] {
            path.move(to: CGPoint(x: x, y: h.minY))
            path.addLine(to: CGPoint(x: x - h.width * 0.08, y: h.maxY))
        }
        for y in [h.minY + h.height * 0.33, h.minY + h.height * 0.68] {
            path.move(to: CGPoint(x: h.minX, y: y))
            path.addLine(to: CGPoint(x: h.maxX, y: y))
        }
        return path
    }
}
