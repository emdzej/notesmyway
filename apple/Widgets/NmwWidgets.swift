//
//  NmwWidgets.swift
//  NmwWidgets
//
//  Pinned and Recent Notes widgets (Home Screen, desktop, Lock Screen).
//  They read the snapshot the app writes to the App Group; tapping a note
//  opens it with a `notesmyway://open` link.
//

import NmwShared
import SwiftUI
import WidgetKit

@main
struct NmwWidgetBundle: WidgetBundle {
    var body: some Widget {
        PinnedNotesWidget()
        RecentNotesWidget()
    }
}

enum NotesKind: String {
    case pinned, recent

    var title: String { self == .pinned ? "Pinned Notes" : "Recent Notes" }
    var symbol: String { self == .pinned ? "pin.fill" : "clock" }

    func notes(in snapshot: WidgetSnapshot) -> [WidgetSnapshot.Note] {
        self == .pinned ? snapshot.allPinned : snapshot.allRecent
    }
}

struct NotesEntry: TimelineEntry {
    let date: Date
    let notes: [WidgetSnapshot.Note]
    let hasNotebooks: Bool
}

struct NotesProvider: TimelineProvider {
    let kind: NotesKind

    func placeholder(in context: Context) -> NotesEntry {
        NotesEntry(date: Date(), notes: Self.sample, hasNotebooks: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (NotesEntry) -> Void) {
        completion(context.isPreview && WidgetSnapshot.load() == nil ? placeholder(in: context) : entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NotesEntry>) -> Void) {
        // The app reloads timelines when notes change; hourly refresh keeps relative dates fresh.
        completion(Timeline(entries: [entry()], policy: .after(Date().addingTimeInterval(3600))))
    }

    private func entry() -> NotesEntry {
        let snapshot = WidgetSnapshot.load()
        return NotesEntry(date: Date(), notes: snapshot.map(kind.notes) ?? [], hasNotebooks: !(snapshot?.notebooks.isEmpty ?? true))
    }

    static let sample: [WidgetSnapshot.Note] = [
        .init(notebookID: "", path: "Travel/Lisbon.md", title: "Lisbon in spring", snippet: "Tram 28 early in the morning", modified: Date(), pinned: true),
        .init(notebookID: "", path: "Recipes/Focaccia.md", title: "Sourdough focaccia", snippet: "Ingredients for one tray", modified: Date().addingTimeInterval(-7200), pinned: true),
        .init(notebookID: "", path: "Projects/Budget.md", title: "Kitchen budget", snippet: "Quotes collected in October", modified: Date().addingTimeInterval(-86400), pinned: false),
        .init(notebookID: "", path: "Reading list.md", title: "Reading list", snippet: "Books for the winter", modified: Date().addingTimeInterval(-172800), pinned: false),
    ]
}

struct PinnedNotesWidget: Widget {
    var body: some WidgetConfiguration { NotesWidgetConfiguration.make(.pinned) }
}

struct RecentNotesWidget: Widget {
    var body: some WidgetConfiguration { NotesWidgetConfiguration.make(.recent) }
}

@MainActor
enum NotesWidgetConfiguration {
    static func make(_ kind: NotesKind) -> some WidgetConfiguration {
        StaticConfiguration(kind: "nmw.\(kind.rawValue)", provider: NotesProvider(kind: kind)) { entry in
            NotesWidgetView(kind: kind, entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName(kind.title)
        .description(kind == .pinned ? "Your pinned notes." : "The notes you changed last.")
        .supportedFamilies(families)
    }

    private static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline]
        #else
        [.systemSmall, .systemMedium, .systemLarge]
        #endif
    }
}
