//
//  ThemeSettingsView.swift
//  NmwUI
//
//  Settings › General › Theme: editor theme, font, size, line spacing, the
//  source view's theme, and the Themes folder for custom JSON themes.
//

#if os(macOS)
import AppKit
#endif
import SwiftUI

struct EditorThemeSection: View {
    @Bindable var appearance = EditorAppearance.shared
    @State private var message: String?

    var body: some View {
        Section {
            Picker("Theme", selection: $appearance.themeID) {
                ForEach(appearance.themes) { theme in
                    Label { Text(theme.name) } icon: { ThemeSwatch(theme: theme) }.tag(theme.id)
                }
            }
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
            #if os(macOS)
            HStack {
                Button("Duplicate as Custom Theme…") { duplicate() }
                Button("Open Themes Folder") { openFolder() }
                Spacer()
                Button("Reload") { appearance.reloadThemes() }
            }
            #endif
            if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
        } header: {
            Text("Theme")
        } footer: {
            Text(footer).foregroundStyle(.secondary)
        }
        .onAppear { appearance.reloadThemes() }
    }

    private var footer: String {
        #if os(macOS)
        "Custom themes are JSON files in the Themes folder; edit a duplicate, then Reload."
        #else
        "Custom themes are JSON files in Files › On My iPhone › Notes my Way › Themes."
        #endif
    }

    #if os(macOS)
    private func duplicate() {
        do {
            let url = try ThemeStore.duplicate(appearance.theme)
            appearance.reloadThemes()
            message = "Saved \(url.lastPathComponent). Edit it, then press Reload."
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            message = error.localizedDescription
        }
    }

    private func openFolder() {
        try? FileManager.default.createDirectory(at: ThemeStore.folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(ThemeStore.folder)
    }
    #endif
}

/// A small preview of a theme: its background with a heading bar, text lines and the link color.
struct ThemeSwatch: View {
    let theme: EditorTheme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = colorScheme == .dark ? theme.dark : theme.light
        let background = color(colors.background) ?? (colorScheme == .dark ? Color(white: 0.12) : .white)
        let text = color(colors.text) ?? .primary
        let heading = color(colors.heading) ?? text
        let link = color(colors.link) ?? Palette.accentColor
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
