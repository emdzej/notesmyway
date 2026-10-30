//
//  EditorTheme.swift
//  NmwUI
//
//  Editor themes (spec §4.5): colors for the formatted view and the
//  markdown source view, fonts, and the code-block highlighting theme, each
//  with a light and a dark palette. Built-in themes plus JSON files the user
//  drops into Application Support/nmw/Themes.
//

#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Foundation
import MarkdownEngine
import SwiftUI

/// A theme as stored in JSON. Every color is optional ("#RRGGBB" or
/// "#RRGGBBAA"); a missing one keeps the engine's built-in look.
public struct EditorTheme: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// "system", "serif", "mono", "rounded", or a PostScript font name.
    public var font: String?
    /// Headings; nil uses `font`.
    public var headingFont: String?
    /// Source view font; nil is the system monospaced font.
    public var sourceFont: String?
    /// HighlighterSwift theme names for code blocks.
    public var codeTheme: CodeTheme?
    /// The modes the theme is made for: "light", "dark"; nil is both. With
    /// one only, the app switches to it while the theme is on.
    public var modes: [String]?
    /// The sidebar's colors, top to bottom (one is a solid fill), with light
    /// text on them; nil washes the sidebar with the page color.
    public var sidebar: [String]?
    public var light: Colors
    public var dark: Colors

    public init(id: String, name: String, font: String? = nil, headingFont: String? = nil, sourceFont: String? = nil,
                codeTheme: CodeTheme? = nil, modes: [String]? = nil, sidebar: [String]? = nil, light: Colors, dark: Colors) {
        self.id = id; self.name = name; self.font = font; self.headingFont = headingFont; self.sourceFont = sourceFont
        self.codeTheme = codeTheme; self.modes = modes; self.sidebar = sidebar; self.light = light; self.dark = dark
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, font, headingFont, sourceFont, codeTheme, modes, sidebar, light, dark
    }

    /// Lenient, for hand-written files: `id` defaults to the name made
    /// file-safe, and a missing palette is empty (the built-in look).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        let rawID = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        id = rawID.trimmingCharacters(in: .whitespaces).isEmpty ? Self.slug(name) : rawID
        font = try c.decodeIfPresent(String.self, forKey: .font)
        headingFont = try c.decodeIfPresent(String.self, forKey: .headingFont)
        sourceFont = try c.decodeIfPresent(String.self, forKey: .sourceFont)
        codeTheme = try c.decodeIfPresent(CodeTheme.self, forKey: .codeTheme)
        modes = try c.decodeIfPresent([String].self, forKey: .modes)
        sidebar = try c.decodeIfPresent([String].self, forKey: .sidebar)
        light = try c.decodeIfPresent(Colors.self, forKey: .light) ?? Colors()
        dark = try c.decodeIfPresent(Colors.self, forKey: .dark) ?? Colors()
    }

    /// "My Theme!" → "my-theme".
    static func slug(_ name: String) -> String {
        let parts = name.lowercased().split { !($0.isLetter || $0.isNumber) }
        let slug = parts.joined(separator: "-")
        return slug.isEmpty ? "theme" : slug
    }

    public struct CodeTheme: Codable, Equatable, Sendable {
        public var light: String
        public var dark: String
    }

    public struct Colors: Codable, Equatable, Sendable {
        public var background: String?
        public var text: String?
        public var mutedText: String?
        public var heading: String?
        public var headingMarker: String?
        public var link: String?
        /// The app's accent (selection, buttons, checkboxes); nil uses `link`.
        public var accent: String?
        public var inlineCode: String?
        public var codeBackground: String?
        public var quoteBar: String?
        public var quoteText: String?
        public var rule: String?
        public var tableBorder: String?
        public var tableHeader: String?
        public var selection: String?
        public var caret: String?
        public var chip: String?
        public var tag: String?
        public var cardBackground: String?
        public var cardBorder: String?
        public var source: SourceColors?

        public init(background: String? = nil, text: String? = nil, mutedText: String? = nil, heading: String? = nil,
                    headingMarker: String? = nil, link: String? = nil, accent: String? = nil, inlineCode: String? = nil, codeBackground: String? = nil,
                    quoteBar: String? = nil, quoteText: String? = nil, rule: String? = nil, tableBorder: String? = nil,
                    tableHeader: String? = nil, selection: String? = nil, caret: String? = nil, chip: String? = nil,
                    tag: String? = nil, cardBackground: String? = nil, cardBorder: String? = nil, source: SourceColors? = nil) {
            self.background = background; self.text = text; self.mutedText = mutedText; self.heading = heading
            self.headingMarker = headingMarker; self.link = link; self.accent = accent; self.inlineCode = inlineCode; self.codeBackground = codeBackground
            self.quoteBar = quoteBar; self.quoteText = quoteText; self.rule = rule; self.tableBorder = tableBorder
            self.tableHeader = tableHeader; self.selection = selection; self.caret = caret; self.chip = chip
            self.tag = tag; self.cardBackground = cardBackground; self.cardBorder = cardBorder; self.source = source
        }
    }

    /// The markdown source view's syntax colors.
    public struct SourceColors: Codable, Equatable, Sendable {
        public var background: String?
        public var text: String?
        public var marker: String?
        public var heading: String?
        public var emphasis: String?
        public var link: String?
        public var url: String?
        public var code: String?
        public var key: String?
        public var attribute: String?
        public var listMarker: String?

        public init(background: String? = nil, text: String? = nil, marker: String? = nil, heading: String? = nil,
                    emphasis: String? = nil, link: String? = nil, url: String? = nil, code: String? = nil,
                    key: String? = nil, attribute: String? = nil, listMarker: String? = nil) {
            self.background = background; self.text = text; self.marker = marker; self.heading = heading
            self.emphasis = emphasis; self.link = link; self.url = url; self.code = code
            self.key = key; self.attribute = attribute; self.listMarker = listMarker
        }
    }
}

// MARK: - Applying

extension EditorTheme {

    /// A light/dark color from the two palettes' values for one key; nil when neither sets it.
    static func color(_ light: String?, _ dark: String?) -> PlatformColor? {
        let l = light.flatMap(Self.parse), d = dark.flatMap(Self.parse)
        guard l != nil || d != nil else { return nil }
        return ThemeColor.dynamic(light: l ?? d!, dark: d ?? l!)
    }

    /// "#RGB", "#RRGGBB" or "#RRGGBBAA".
    static func parse(_ hex: String) -> PlatformColor? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else { return nil }
        let hasAlpha = s.count == 8
        let r = CGFloat((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let g = CGFloat((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let b = CGFloat((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let a = hasAlpha ? CGFloat(value & 0xFF) / 255 : 1
        return PlatformColor(red: r, green: g, blue: b, alpha: a)
    }

    private func pair(_ key: KeyPath<Colors, String?>) -> PlatformColor? {
        Self.color(light[keyPath: key], dark[keyPath: key])
    }

    private func sourcePair(_ key: KeyPath<SourceColors, String?>) -> PlatformColor? {
        Self.color(light.source?[keyPath: key], dark.source?[keyPath: key])
    }

    /// Writes the formatted-view colors and heading font into `theme`.
    func apply(to theme: inout MarkdownEditorTheme) {
        if let c = pair(\.text) { theme.bodyText = c; theme.strikethroughColor = c }
        if let c = pair(\.mutedText) { theme.mutedText = c }
        if let c = pair(\.headingMarker) ?? pair(\.mutedText) { theme.headingMarker = c }
        if let c = pair(\.link) { theme.link = c; theme.incompleteLink = c }
        theme.background = pair(\.background)
        theme.headingText = pair(\.heading)
        theme.headingFontName = (headingFont ?? font).map(Self.engineFontName)
        theme.inlineCodeText = pair(\.inlineCode)
        theme.blockquoteBar = pair(\.quoteBar)
        theme.blockquoteText = pair(\.quoteText)
        theme.rule = pair(\.rule)
        theme.tableBorder = pair(\.tableBorder)
        theme.tableHeaderBackground = pair(\.tableHeader)
        theme.selection = pair(\.selection)
        theme.caret = pair(\.caret)
        theme.chipBackground = pair(\.chip)
        theme.tagChip = pair(\.tag)
        theme.cardBackground = pair(\.cardBackground)
        theme.cardBorder = pair(\.cardBorder)
    }

    /// Writes the source view's colors and font into `source`.
    func apply(to source: inout SourceModeStyle) {
        source.fontName = sourceFont.map(Self.engineFontName)
        source.background = sourcePair(\.background) ?? pair(\.background)
        source.textColor = sourcePair(\.text) ?? pair(\.text)
        source.markerColor = sourcePair(\.marker)
        source.headingColor = sourcePair(\.heading) ?? pair(\.heading)
        source.emphasisColor = sourcePair(\.emphasis)
        source.linkColor = sourcePair(\.link) ?? pair(\.link)
        source.urlColor = sourcePair(\.url)
        source.listMarkerColor = sourcePair(\.listMarker)
        if let c = sourcePair(\.code) { source.codeColor = c }
        if let c = sourcePair(\.key) { source.keyColor = c }
        if let c = sourcePair(\.attribute) { source.attributeColor = c }
    }

    /// The app's accent: `accent`, else `link`; nil when the theme sets neither.
    var accentColor: PlatformColor? {
        Self.color(light.accent ?? light.link, dark.accent ?? dark.link)
    }

    /// The sidebar gradient's colors; nil when the theme doesn't set them.
    var sidebarColors: [Color]? {
        guard let sidebar, !sidebar.isEmpty else { return nil }
        let colors = sidebar.compactMap(Self.parse).map { Color($0) }
        return colors.count == sidebar.count ? colors : nil
    }

    /// The page (editor) background; nil keeps the system's.
    var pageColor: PlatformColor? { pair(\.background) }

    var supportsLight: Bool { modes.map { $0.contains { $0.lowercased() == "light" } } ?? true }
    var supportsDark: Bool { modes.map { $0.contains { $0.lowercased() == "dark" } } ?? true }

    /// The scheme a light- or dark-only theme needs; nil when it has both.
    var requiredScheme: ColorScheme? {
        switch (supportsLight, supportsDark) {
        case (true, false): .light
        case (false, true): .dark
        default: nil
        }
    }

    /// The code-block background as a light/dark pair, if the theme sets it.
    var codeBackgrounds: (light: PlatformColor, dark: PlatformColor)? {
        let l = light.codeBackground.flatMap(Self.parse), d = dark.codeBackground.flatMap(Self.parse)
        guard l != nil || d != nil else { return nil }
        return (l ?? d!, d ?? l!)
    }

    /// Theme font names to engine font names.
    static func engineFontName(_ name: String) -> String {
        switch name.lowercased() {
        case "system", "sans", "sans-serif": MarkdownFontName.system
        case "serif": MarkdownFontName.serif
        case "mono", "monospace", "monospaced": MarkdownFontName.monospaced
        case "rounded": MarkdownFontName.rounded
        default: name
        }
    }
}

enum ThemeColor {
    static func dynamic(light: PlatformColor, dark: PlatformColor) -> PlatformColor {
        #if os(macOS)
        NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
        #else
        UIColor { $0.userInterfaceStyle == .dark ? dark : light }
        #endif
    }
}

// MARK: - Built-in themes

extension EditorTheme {
    static let defaultID = "nmw"

    static let builtIn: [EditorTheme] = [notesMyWay, paper, github, solarized, nord, dracula, mono]

    static let notesMyWay = EditorTheme(
        id: "nmw", name: "Notes my Way",
        codeTheme: CodeTheme(light: "atom-one-light", dark: "atom-one-dark"),
        // The icon's gradient, as the "My Way" sidebar.
        sidebar: ["#148093", "#0A345C"],
        light: Colors(link: "#1A8FA8", tag: "#1A8FA8", source: SourceColors(heading: "#1A8FA8")),
        dark: Colors(link: "#5CCFDB", tag: "#5CCFDB", source: SourceColors(heading: "#5CCFDB"))
    )

    static let paper = EditorTheme(
        id: "paper", name: "Paper", font: "serif", headingFont: "serif",
        codeTheme: CodeTheme(light: "gruvbox-light-soft", dark: "gruvbox-dark-soft"),
        light: Colors(background: "#FBF7EF", text: "#2B2620", mutedText: "#8A7F70", heading: "#3B2F22",
                      link: "#A4552A", codeBackground: "#F2EBDD", quoteBar: "#D9CBB3", quoteText: "#6F6556",
                      rule: "#E0D4BF", tableBorder: "#D9CBB3", tableHeader: "#F3ECDD", selection: "#EADBC0",
                      caret: "#A4552A", chip: "#EFE6D6", tag: "#A4552A", cardBackground: "#F6F0E4", cardBorder: "#E0D4BF",
                      source: SourceColors(marker: "#B3A691", heading: "#8F4A24", url: "#A39886", code: "#7A5C2E", key: "#8F4A24", attribute: "#7D6A9E")),
        dark: Colors(background: "#1F1B16", text: "#E8DFD0", mutedText: "#A39886", heading: "#F2E6D2",
                     link: "#E0975F", codeBackground: "#2A251E", quoteBar: "#4A4135", quoteText: "#B8AD9A",
                     rule: "#3E372D", tableBorder: "#4A4135", tableHeader: "#29241D", selection: "#4A3B2A",
                     caret: "#E0975F", chip: "#2E281F", tag: "#E0975F", cardBackground: "#26211A", cardBorder: "#3E372D",
                     source: SourceColors(marker: "#7A705F", heading: "#E8A46F", url: "#8C8273", code: "#D8B67A", key: "#E8A46F", attribute: "#B9A6D9"))
    )

    static let github = EditorTheme(
        id: "github", name: "GitHub",
        codeTheme: CodeTheme(light: "github", dark: "github-dark"),
        light: Colors(background: "#FFFFFF", text: "#1F2328", mutedText: "#59636E", heading: "#1F2328",
                      link: "#0969DA", codeBackground: "#F6F8FA", quoteBar: "#D1D9E0", quoteText: "#59636E",
                      rule: "#D1D9E0", tableBorder: "#D1D9E0", tableHeader: "#F6F8FA", selection: "#B6E3FF",
                      chip: "#EFF2F5", tag: "#0969DA", cardBackground: "#F6F8FA", cardBorder: "#D1D9E0",
                      source: SourceColors(heading: "#0550AE", url: "#59636E", code: "#CF222E", key: "#953800", attribute: "#8250DF")),
        dark: Colors(background: "#0D1117", text: "#F0F6FC", mutedText: "#9198A1", heading: "#F0F6FC",
                     link: "#4493F8", codeBackground: "#151B23", quoteBar: "#3D444D", quoteText: "#9198A1",
                     rule: "#3D444D", tableBorder: "#3D444D", tableHeader: "#151B23", selection: "#1F4A7A",
                     chip: "#21262D", tag: "#4493F8", cardBackground: "#151B23", cardBorder: "#3D444D",
                     source: SourceColors(heading: "#79C0FF", url: "#9198A1", code: "#FF7B72", key: "#FFA657", attribute: "#D2A8FF"))
    )

    static let solarized = EditorTheme(
        id: "solarized", name: "Solarized",
        codeTheme: CodeTheme(light: "solarized-light", dark: "solarized-dark"),
        light: Colors(background: "#FDF6E3", text: "#586E75", mutedText: "#93A1A1", heading: "#CB4B16",
                      link: "#268BD2", inlineCode: "#D33682", codeBackground: "#EEE8D5", quoteBar: "#DDD6C1",
                      quoteText: "#839496", rule: "#E4DCC4", tableBorder: "#DDD6C1", tableHeader: "#EEE8D5",
                      selection: "#E6DDBF", caret: "#268BD2", chip: "#EEE8D5", tag: "#2AA198",
                      cardBackground: "#F5EEDA", cardBorder: "#DDD6C1",
                      source: SourceColors(heading: "#CB4B16", link: "#268BD2", url: "#93A1A1", code: "#2AA198", key: "#B58900", attribute: "#6C71C4", listMarker: "#859900")),
        dark: Colors(background: "#002B36", text: "#93A1A1", mutedText: "#657B83", heading: "#CB4B16",
                     link: "#268BD2", inlineCode: "#D33682", codeBackground: "#073642", quoteBar: "#0E4B5A",
                     quoteText: "#839496", rule: "#0E4B5A", tableBorder: "#0E4B5A", tableHeader: "#073642",
                     selection: "#0F4C5C", caret: "#268BD2", chip: "#073642", tag: "#2AA198",
                     cardBackground: "#05313D", cardBorder: "#0E4B5A",
                     source: SourceColors(heading: "#CB4B16", link: "#268BD2", url: "#657B83", code: "#2AA198", key: "#B58900", attribute: "#6C71C4", listMarker: "#859900"))
    )

    static let nord = EditorTheme(
        id: "nord", name: "Nord",
        codeTheme: CodeTheme(light: "xcode", dark: "nord"),
        light: Colors(background: "#ECEFF4", text: "#2E3440", mutedText: "#4C566A", heading: "#5E81AC",
                      link: "#5E81AC", codeBackground: "#E5E9F0", quoteBar: "#D8DEE9", quoteText: "#4C566A",
                      rule: "#D8DEE9", tableBorder: "#D8DEE9", tableHeader: "#E5E9F0", selection: "#D8DEE9",
                      caret: "#5E81AC", chip: "#E5E9F0", tag: "#5E81AC", cardBackground: "#E5E9F0", cardBorder: "#D8DEE9",
                      source: SourceColors(heading: "#5E81AC", url: "#4C566A", code: "#A3BE8C", key: "#D08770", attribute: "#B48EAD", listMarker: "#81A1C1")),
        dark: Colors(background: "#2E3440", text: "#D8DEE9", mutedText: "#7B88A1", heading: "#88C0D0",
                     link: "#88C0D0", codeBackground: "#3B4252", quoteBar: "#4C566A", quoteText: "#A0A9BA",
                     rule: "#434C5E", tableBorder: "#4C566A", tableHeader: "#3B4252", selection: "#434C5E",
                     caret: "#88C0D0", chip: "#3B4252", tag: "#8FBCBB", cardBackground: "#3B4252", cardBorder: "#4C566A",
                     source: SourceColors(heading: "#88C0D0", url: "#7B88A1", code: "#A3BE8C", key: "#D08770", attribute: "#B48EAD", listMarker: "#81A1C1"))
    )

    static let dracula = EditorTheme(
        id: "dracula", name: "Dracula",
        codeTheme: CodeTheme(light: "atom-one-light", dark: "dracula"),
        light: Colors(background: "#FFFBEB", text: "#1F1F1F", mutedText: "#6C664B", heading: "#644AC9",
                      link: "#036A96", inlineCode: "#14710A", codeBackground: "#EFEDDC", quoteBar: "#DEDCCB",
                      quoteText: "#635D44", rule: "#DEDCCB", tableBorder: "#DEDCCB", tableHeader: "#F4F1DE",
                      selection: "#CFCFDE", caret: "#644AC9", chip: "#EFEDDC", tag: "#A3144D",
                      cardBackground: "#F7F3E1", cardBorder: "#DEDCCB",
                      source: SourceColors(heading: "#644AC9", url: "#6C664B", code: "#14710A", key: "#A34D14", attribute: "#A3144D", listMarker: "#036A96")),
        dark: Colors(background: "#282A36", text: "#F8F8F2", mutedText: "#6272A4", heading: "#BD93F9",
                     link: "#8BE9FD", inlineCode: "#50FA7B", codeBackground: "#21222C", quoteBar: "#44475A",
                     quoteText: "#A4A9C9", rule: "#44475A", tableBorder: "#44475A", tableHeader: "#21222C",
                     selection: "#44475A", caret: "#FF79C6", chip: "#343746", tag: "#FF79C6",
                     cardBackground: "#21222C", cardBorder: "#44475A",
                     source: SourceColors(marker: "#6272A4", heading: "#BD93F9", emphasis: "#F1FA8C", link: "#8BE9FD", url: "#6272A4", code: "#50FA7B", key: "#FFB86C", attribute: "#FF79C6", listMarker: "#FF79C6"))
    )

    static let mono = EditorTheme(
        id: "mono", name: "Mono", font: "mono", headingFont: "mono",
        codeTheme: CodeTheme(light: "xcode", dark: "xcode-dusk"),
        light: Colors(background: "#FAFAF7", text: "#222222", mutedText: "#7A7A7A", heading: "#111111",
                      link: "#3355AA", codeBackground: "#F0F0EB", quoteBar: "#CFCFC8", quoteText: "#666666",
                      rule: "#D8D8D2", tableBorder: "#CFCFC8", tableHeader: "#F0F0EB", selection: "#E2E2DA",
                      caret: "#222222", chip: "#EDEDE7", tag: "#3355AA", cardBackground: "#F3F3EE", cardBorder: "#D8D8D2",
                      source: SourceColors(marker: "#9A9A9A", heading: "#111111", url: "#8A8A8A", code: "#555555", key: "#333333", attribute: "#777777", listMarker: "#555555")),
        dark: Colors(background: "#161616", text: "#DDDDDD", mutedText: "#8A8A8A", heading: "#FFFFFF",
                     link: "#8AB4F8", codeBackground: "#222222", quoteBar: "#3A3A3A", quoteText: "#A8A8A8",
                     rule: "#333333", tableBorder: "#3A3A3A", tableHeader: "#202020", selection: "#3A3A3A",
                     caret: "#DDDDDD", chip: "#262626", tag: "#8AB4F8", cardBackground: "#1E1E1E", cardBorder: "#333333",
                     source: SourceColors(marker: "#6A6A6A", heading: "#FFFFFF", url: "#7A7A7A", code: "#BBBBBB", key: "#DDDDDD", attribute: "#999999", listMarker: "#AAAAAA"))
    )
}

// MARK: - Store

/// Built-in themes plus `*.json` / `*.nmwtheme` themes from the Themes folder.
@MainActor
enum ThemeStore {

    /// Application Support/nmw/Themes (inside the sandbox container; on iOS
    /// it's under the app's folder in Files).
    static var folder: URL {
        #if os(macOS)
        let base = URL.applicationSupportDirectory.appending(path: "nmw", directoryHint: .isDirectory)
        #else
        // Documents is what Files shows for the app.
        let base = URL.documentsDirectory
        #endif
        return base.appending(path: "Themes", directoryHint: .isDirectory)
    }

    /// Themes from JSON files; unreadable files are skipped. A user theme
    /// with a built-in's id replaces it.
    static func userThemes() -> [EditorTheme] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
        return files
            .filter { fileExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(EditorTheme.self, from: data)
            }
    }

    static let fileExtension = "nmwtheme"
    static let fileExtensions: Set<String> = ["json", fileExtension]

    /// The file in the Themes folder a user theme was read from.
    static func file(for id: String) -> URL? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return nil }
        return files.first { url in
            guard fileExtensions.contains(url.pathExtension.lowercased()), let data = try? Data(contentsOf: url) else { return false }
            return (try? JSONDecoder().decode(EditorTheme.self, from: data))?.id == id
        }
    }

    static func isUserTheme(_ id: String) -> Bool { userThemes().contains { $0.id == id } }

    // MARK: Installing

    enum InstallError: LocalizedError, Equatable {
        case unreadable
        case invalid(String)

        var errorDescription: String? {
            switch self {
            case .unreadable: "The file couldn’t be read."
            case .invalid(let reason): reason
            }
        }
    }

    /// Reads and checks a theme file: valid JSON with a name, and colors
    /// that are all "#RGB", "#RRGGBB" or "#RRGGBBAA".
    static func validate(_ data: Data) throws(InstallError) -> EditorTheme {
        let theme: EditorTheme
        do {
            theme = try JSONDecoder().decode(EditorTheme.self, from: data)
        } catch let DecodingError.keyNotFound(key, _) {
            throw .invalid("It has no “\(key.stringValue)”.")
        } catch let DecodingError.typeMismatch(_, context), let DecodingError.valueNotFound(_, context) {
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            throw .invalid("“\(path)” has the wrong kind of value.")
        } catch DecodingError.dataCorrupted {
            throw .invalid("It isn’t a theme: the file isn’t valid JSON.")
        } catch {
            throw .invalid("It isn’t a theme.")
        }
        guard !theme.name.trimmingCharacters(in: .whitespaces).isEmpty else { throw .invalid("Its name is empty.") }
        if let modes = theme.modes {
            let known = modes.map { $0.lowercased() }
            guard !known.isEmpty, known.allSatisfy({ ["light", "dark"].contains($0) }) else {
                throw .invalid("“modes” must list \"light\", \"dark\" or both.")
            }
        }
        var bad = badColors(in: theme)
        if let sidebar = theme.sidebar, sidebar.contains(where: { EditorTheme.parse($0) == nil }) { bad.append("sidebar") }
        if !bad.isEmpty {
            throw .invalid("These colors aren’t hex colors like #1A8FA8: \(bad.prefix(4).joined(separator: ", ")).")
        }
        return theme
    }

    /// Keys like "light.link" whose value doesn't parse.
    static func badColors(in theme: EditorTheme) -> [String] {
        var bad: [String] = []
        for (mode, colors) in [("light", theme.light), ("dark", theme.dark)] {
            guard let data = try? JSONEncoder().encode(colors),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            for (key, value) in dict.sorted(by: { $0.key < $1.key }) {
                if let hex = value as? String, EditorTheme.parse(hex) == nil { bad.append("\(mode).\(key)") }
                if let source = value as? [String: Any] {
                    for (k, v) in source.sorted(by: { $0.key < $1.key }) {
                        if let hex = v as? String, EditorTheme.parse(hex) == nil { bad.append("\(mode).source.\(k)") }
                    }
                }
            }
        }
        return bad
    }

    /// A theme already installed or built in with the same id.
    static func existing(_ theme: EditorTheme) -> EditorTheme? {
        all().first { $0.id == theme.id }
    }

    /// Writes `theme` to the Themes folder, replacing a user theme with the
    /// same id (a built-in with that id is then hidden by it).
    @discardableResult
    static func install(_ theme: EditorTheme) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let old = file(for: theme.id) { try FileManager.default.removeItem(at: old) }
        let url = folder.appending(path: "\(fileName(theme.id)).json")
        try encoded(theme).write(to: url, options: .atomic)
        return url
    }

    /// `theme` with an id and name that don't clash: "Name 2", "name-2".
    static func keepingBoth(_ theme: EditorTheme) -> EditorTheme {
        let themes = all()
        var copy = theme
        var n = 2
        while themes.contains(where: { $0.id == copy.id || $0.name == copy.name }) {
            copy.id = "\(theme.id)-\(n)"
            copy.name = "\(theme.name) \(n)"
            n += 1
        }
        return copy
    }

    /// Removes a user theme's file.
    static func delete(id: String) throws {
        if let url = file(for: id) { try FileManager.default.removeItem(at: url) }
    }

    /// A `.nmwtheme` copy of `theme` in a temporary folder, to share.
    static func exportFile(_ theme: EditorTheme) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "nmw-themes", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "\(fileName(theme.name)).\(fileExtension)")
        try encoded(theme).write(to: url, options: .atomic)
        return url
    }

    private static func fileName(_ s: String) -> String {
        let cleaned = s.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return cleaned.isEmpty ? "theme" : cleaned
    }

    private static func encoded(_ theme: EditorTheme) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(theme)
    }

    static func all() -> [EditorTheme] {
        let user = userThemes()
        let ids = Set(user.map(\.id))
        return EditorTheme.builtIn.filter { !ids.contains($0.id) } + user
    }

    static func theme(id: String) -> EditorTheme {
        all().first { $0.id == id } ?? .notesMyWay
    }

    /// Writes a copy of `theme` as a new JSON file to edit; returns its URL.
    static func duplicate(_ theme: EditorTheme) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var copy = theme
        var n = 1
        var url: URL
        repeat {
            copy.id = n == 1 ? "\(theme.id)-custom" : "\(theme.id)-custom-\(n)"
            url = folder.appending(path: "\(copy.id).json")
            n += 1
        } while FileManager.default.fileExists(atPath: url.path)
        copy.name = "\(theme.name) (Custom)"
        try encoded(copy).write(to: url, options: .atomic)
        return url
    }

    /// The JSON text for `theme`, for previews and tests.
    static func json(_ theme: EditorTheme) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(theme)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}
