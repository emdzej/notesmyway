//
//  ThemeSettingsView.swift
//  NmwUI
//
//  Settings › General: the theme picker (it colors the whole app), the
//  editor's text (font, size, line spacing, the source view's theme), and
//  the installed themes: install from a file, duplicate, share, delete.
//  `ThemeInstaller` handles theme files opened from Files, Finder or Mail.
//

#if os(macOS)
import AppKit
#endif
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// `.nmwtheme`: a theme as JSON (declared in the app's Info.plist).
    static let nmwTheme = UTType(exportedAs: "pl.emdzej.notesmyway.theme", conformingTo: .json)
}

extension EditorTheme: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .nmwTheme) { theme in
            SentTransferredFile(try await ThemeStore.exportFile(theme))
        }
    }
}

/// The theme picker, for Settings › General › Look.
struct ThemePicker: View {
    @Bindable var appearance = EditorAppearance.shared

    var body: some View {
        Picker("Theme", selection: $appearance.themeID) {
            ForEach(appearance.themes) { theme in
                Label { Text(theme.name) } icon: { ThemeSwatch(theme: theme) }.tag(theme.id)
            }
        }
    }
}

/// The Appearance picker; fixed (and saying so) while a light- or dark-only theme is on.
struct AppearancePicker: View {
    @AppStorage(AppAppearance.key) private var appearance = AppAppearance.system
    private var editor = EditorAppearance.shared

    var body: some View {
        if let scheme = editor.theme.requiredScheme {
            LabeledContent("Appearance") {
                Text(scheme == .dark ? "Dark (set by theme)" : "Light (set by theme)")
            }
            .help("\(editor.theme.name) has only a \(scheme == .dark ? "dark" : "light") mode.")
        } else {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
            }
        }
    }
}

/// Font, size, line spacing and the source view's theme.
struct EditorTextSection: View {
    @Bindable var appearance = EditorAppearance.shared

    var body: some View {
        Section("Text") {
            Picker("Font", selection: $appearance.font) {
                ForEach(EditorAppearance.Font.allCases) { Text($0.title).tag($0) }
            }
            LabeledContent("Text size") {
                HStack {
                    Slider(value: $appearance.fontSize, in: EditorAppearance.fontSizes, step: 1)
                        .frame(maxWidth: 180)
                    Text("\(Int(appearance.fontSize)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
            }
            LabeledContent("Line spacing") {
                HStack {
                    Slider(value: $appearance.lineSpacing, in: EditorAppearance.lineSpacings, step: 0.1)
                        .frame(maxWidth: 180)
                    Text(String(format: "%.1f×", appearance.lineSpacing)).monospacedDigit().frame(width: 44, alignment: .trailing)
                }
            }
            Picker("Markdown source", selection: $appearance.sourceThemeID) {
                Text("Same as Theme").tag("")
                Divider()
                ForEach(appearance.themes) { theme in
                    Label { Text(theme.name) } icon: { ThemeSwatch(theme: theme) }.tag(theme.id)
                }
            }
        }
    }
}

/// Installed themes, and installing, duplicating and sharing.
struct ThemeLibrarySection: View {
    @Bindable var appearance = EditorAppearance.shared
    private var installer = ThemeInstaller.shared
    @State private var importing = false
    @State private var deleting: EditorTheme?
    @State private var message: String?

    private var installed: [EditorTheme] { appearance.themes.filter { appearance.userThemeIDs.contains($0.id) } }

    var body: some View {
        Section {
            ForEach(installed) { theme in
                HStack {
                    ThemeSwatch(theme: theme)
                    Text(theme.name)
                    if let scheme = theme.requiredScheme {
                        Text(scheme == .dark ? "Dark only" : "Light only").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if theme.id == appearance.themeID {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                    Menu {
                        Button("Use", systemImage: "paintpalette") { appearance.themeID = theme.id }
                        ShareLink(item: theme, preview: SharePreview(theme.name)) {
                            Label("Share…", systemImage: "square.and.arrow.up")
                        }
                        Button("Duplicate", systemImage: "plus.square.on.square") { duplicate(theme) }
                        #if os(macOS)
                        Button("Show in Finder", systemImage: "folder") {
                            if let url = ThemeStore.file(for: theme.id) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        }
                        #endif
                        Divider()
                        Button("Delete", systemImage: "trash", role: .destructive) { deleting = theme }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .fixedSize()
                    .accessibilityLabel("Actions for \(theme.name)")
                }
                .contentShape(Rectangle())
                .contextMenu {
                    Button("Use", systemImage: "paintpalette") { appearance.themeID = theme.id }
                    Button("Delete", systemImage: "trash", role: .destructive) { deleting = theme }
                }
            }
            Button("Install Theme…", systemImage: "square.and.arrow.down") { importing = true }
            Button("Duplicate “\(appearance.theme.name)”", systemImage: "plus.square.on.square") { duplicate(appearance.theme) }
            ShareLink(item: appearance.theme, preview: SharePreview(appearance.theme.name)) {
                Label("Share “\(appearance.theme.name)”…", systemImage: "square.and.arrow.up")
            }
            #if os(macOS)
            HStack {
                Button("Open Themes Folder") { openFolder() }
                Spacer()
                Button("Reload") { appearance.reloadThemes() }
            }
            #endif
            if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
        } header: {
            Text("Themes")
        } footer: {
            Text(footer).foregroundStyle(.secondary)
        }
        .onAppear { appearance.reloadThemes() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.nmwTheme, .json]) { result in
            if case .success(let url) = result { installer.open(url) }
        }
        #if os(macOS)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { ThemeStore.fileExtensions.contains($0.pathExtension.lowercased()) }) else { return false }
            installer.open(url)
            return true
        }
        #endif
        .confirmationDialog("Delete “\(deleting?.name ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete Theme", role: .destructive) { if let deleting { delete(deleting) } }
        } message: {
            Text("Its file is removed from the Themes folder.")
        }
    }

    private var footer: String {
        #if os(macOS)
        "Open a .nmwtheme file, or drop one here, to install it. Themes are JSON files in the Themes folder: edit a duplicate, then Reload."
        #else
        "Tap a .nmwtheme file in Files, Mail or Messages to install it. Themes are JSON files in Files › On My iPhone › Notes my Way › Themes."
        #endif
    }

    private func duplicate(_ theme: EditorTheme) {
        do {
            let url = try ThemeStore.duplicate(theme)
            appearance.reloadThemes()
            #if os(macOS)
            message = "Saved \(url.lastPathComponent). Edit it, then press Reload."
            NSWorkspace.shared.activateFileViewerSelecting([url])
            #else
            message = "Saved \(url.lastPathComponent) in the Themes folder."
            #endif
        } catch {
            message = error.localizedDescription
        }
    }

    private func delete(_ theme: EditorTheme) {
        do {
            try ThemeStore.delete(id: theme.id)
            appearance.reloadThemes()
            if !appearance.themes.contains(where: { $0.id == appearance.themeID }) { appearance.themeID = EditorTheme.defaultID }
            if !appearance.sourceThemeID.isEmpty, !appearance.themes.contains(where: { $0.id == appearance.sourceThemeID }) {
                appearance.sourceThemeID = ""
            }
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    #if os(macOS)
    private func openFolder() {
        try? FileManager.default.createDirectory(at: ThemeStore.folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(ThemeStore.folder)
    }
    #endif
}

// MARK: - Installing

/// Installs theme files: checks them, then asks (install / replace / keep both).
@MainActor
@Observable
final class ThemeInstaller {
    static let shared = ThemeInstaller()

    struct Pending: Identifiable {
        let id = UUID()
        var theme: EditorTheme
        /// A built-in or installed theme with the same id.
        var existing: EditorTheme?
    }

    var pending: Pending?
    var failure: String?
    /// Settings views on screen; while one is, it shows the alerts (it's on top).
    var settingsShowing = 0

    static func isTheme(_ url: URL) -> Bool {
        url.isFileURL && url.pathExtension.lowercased() == ThemeStore.fileExtension
    }

    func open(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        var data: Data?
        // Files outside the sandbox (iCloud Drive, Mail) read through a coordinator.
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: nil) { data = try? Data(contentsOf: $0) }
        guard let data else {
            failure = "“\(url.lastPathComponent)” couldn’t be read."
            return
        }
        open(data, name: url.lastPathComponent)
    }

    func open(_ data: Data, name: String) {
        do {
            let theme = try ThemeStore.validate(data)
            pending = Pending(theme: theme, existing: ThemeStore.existing(theme))
        } catch {
            failure = "“\(name)” can’t be installed. \(error.localizedDescription)"
        }
    }

    func install(_ theme: EditorTheme, use: Bool) {
        do {
            try ThemeStore.install(theme)
            let appearance = EditorAppearance.shared
            appearance.reloadThemes()
            if use { appearance.themeID = theme.id }
        } catch {
            failure = "“\(theme.name)” couldn’t be installed. \(error.localizedDescription)"
        }
    }
}

extension View {
    /// The installer's alerts; `inSettings` for the Settings view.
    func themeInstallAlerts(inSettings: Bool = false) -> some View {
        modifier(ThemeInstallAlerts(inSettings: inSettings))
    }
}

private struct ThemeInstallAlerts: ViewModifier {
    let inSettings: Bool
    @Bindable private var installer = ThemeInstaller.shared

    private var active: Bool { inSettings || installer.settingsShowing == 0 }

    func body(content: Content) -> some View {
        content
            .onAppear { if inSettings { installer.settingsShowing += 1 } }
            .onDisappear { if inSettings { installer.settingsShowing -= 1 } }
            .alert(title, isPresented: Binding(get: { active && installer.pending != nil }, set: { if !$0 { installer.pending = nil } }),
                   presenting: installer.pending) { pending in
                if let existing = pending.existing {
                    Button(ThemeStore.isUserTheme(existing.id) ? "Replace" : "Replace Built-in") {
                        installer.install(pending.theme, use: true)
                    }
                    Button("Keep Both") { installer.install(ThemeStore.keepingBoth(pending.theme), use: true) }
                } else {
                    Button("Install and Use") { installer.install(pending.theme, use: true) }
                    Button("Install") { installer.install(pending.theme, use: false) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { pending in
                Text(message(pending))
            }
            .alert("Can’t Install Theme", isPresented: Binding(get: { active && installer.failure != nil }, set: { if !$0 { installer.failure = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(installer.failure ?? "")
            }
    }

    private var title: String {
        guard let pending = installer.pending else { return "" }
        if let existing = pending.existing { return "“\(existing.name)” Is Already Installed" }
        return "Install “\(pending.theme.name)”?"
    }

    private func message(_ pending: ThemeInstaller.Pending) -> String {
        let modes = switch pending.theme.requiredScheme {
        case .dark: "It has only a dark mode, so the app switches to dark while it’s on."
        case .light: "It has only a light mode, so the app switches to light while it’s on."
        default: "It has light and dark modes."
        }
        if let existing = pending.existing {
            let what = ThemeStore.isUserTheme(existing.id) ? "Replace it" : "Replace the built-in theme"
            return "\(what) with this file, or keep both. \(modes)"
        }
        return modes
    }
}

/// A small preview of a theme: its background with a heading bar, text lines and the link color.
struct ThemeSwatch: View {
    let theme: EditorTheme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // A one-mode theme always shows that mode.
        let dark = theme.requiredScheme.map { $0 == .dark } ?? (colorScheme == .dark)
        let colors = dark ? theme.dark : theme.light
        let background = color(colors.background) ?? (dark ? Color(white: 0.12) : .white)
        let text = color(colors.text) ?? (dark ? .white : .black)
        let heading = color(colors.heading) ?? text
        let link = color(colors.accent ?? colors.link) ?? Color(Palette.accent)
        RoundedRectangle(cornerRadius: 3)
            .fill(background)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Capsule().fill(heading).frame(width: 10, height: 2.5)
                    Capsule().fill(text.opacity(0.7)).frame(width: 13, height: 1.5)
                    Capsule().fill(link).frame(width: 8, height: 1.5)
                }
                .padding(3)
            }
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.secondary.opacity(0.4), lineWidth: 0.5))
            .frame(width: 20, height: 15)
    }

    private func color(_ hex: String?) -> Color? {
        hex.flatMap(EditorTheme.parse).map(Color.init)
    }
}
