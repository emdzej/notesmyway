//
//  EditorAppearance.swift
//  NmwUI
//
//  The editor's look on this device: theme, font, size, line spacing and
//  the source view's theme. Observable, so open editors restyle as soon as
//  a setting changes; each value is mirrored to UserDefaults (`nmw.theme`, …).
//

import Foundation
import MarkdownEngine
import MarkdownEngineCodeBlocks
import Observation
import SwiftUI

@MainActor
@Observable
public final class EditorAppearance {
    public static let shared = EditorAppearance()

    /// Font choice; `.theme` uses the theme's own font.
    public enum Font: String, CaseIterable, Identifiable, Sendable {
        case theme, system, serif, mono
        public var id: String { rawValue }
        var title: String {
            switch self {
            case .theme: "Theme’s Font"
            case .system: "System"
            case .serif: "Serif"
            case .mono: "Monospaced"
            }
        }
    }

    enum Key {
        static let theme = "nmw.theme"
        static let font = "nmw.editorFont"
        static let fontSize = "nmw.editorFontSize"
        static let lineSpacing = "nmw.editorLineSpacing"
        static let sourceTheme = "nmw.sourceTheme"
    }

    #if os(macOS)
    static let defaultFontSize: Double = 16
    #else
    static let defaultFontSize: Double = 17
    #endif
    static let fontSizes: ClosedRange<Double> = 11...28
    static let lineSpacings: ClosedRange<Double> = 1.0...1.8

    private let defaults: UserDefaults

    public var themeID: String { didSet { defaults.set(themeID, forKey: Key.theme); reloadThemes() } }
    public var font: Font { didSet { defaults.set(font.rawValue, forKey: Key.font) } }
    public var fontSize: Double { didSet { defaults.set(fontSize, forKey: Key.fontSize) } }
    /// Line height multiplier, 1 = the font's natural line height.
    public var lineSpacing: Double { didSet { defaults.set(lineSpacing, forKey: Key.lineSpacing) } }
    /// Theme for the source view; empty follows `themeID`.
    public var sourceThemeID: String { didSet { defaults.set(sourceThemeID, forKey: Key.sourceTheme); reloadThemes() } }

    /// All themes (built-in and user), refreshed by `reloadThemes()`.
    public private(set) var themes: [EditorTheme] = EditorTheme.builtIn
    /// Bumped when user theme files are re-read, so editors restyle.
    private(set) var themesRevision = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        themeID = defaults.string(forKey: Key.theme) ?? EditorTheme.defaultID
        font = defaults.string(forKey: Key.font).flatMap(Font.init(rawValue:)) ?? .theme
        let size = defaults.double(forKey: Key.fontSize)
        fontSize = size > 0 ? size : Self.defaultFontSize
        let spacing = defaults.double(forKey: Key.lineSpacing)
        lineSpacing = spacing > 0 ? spacing : 1
        sourceThemeID = defaults.string(forKey: Key.sourceTheme) ?? ""
        themes = ThemeStore.all()
    }

    /// Re-reads the Themes folder.
    public func reloadThemes() {
        let fresh = ThemeStore.all()
        if fresh != themes {
            themes = fresh
            themesRevision += 1
        }
    }

    var theme: EditorTheme { themes.first { $0.id == themeID } ?? .notesMyWay }
    var sourceTheme: EditorTheme {
        sourceThemeID.isEmpty ? theme : (themes.first { $0.id == sourceThemeID } ?? theme)
    }

    /// The engine font name for the body text.
    var fontName: String {
        switch font {
        case .theme: theme.font.map(EditorTheme.engineFontName) ?? MarkdownFontName.system
        case .system: MarkdownFontName.system
        case .serif: MarkdownFontName.serif
        case .mono: MarkdownFontName.monospaced
        }
    }

    /// Changes whenever anything the engine can't compare by value changes.
    var revision: String {
        "\(themeID)|\(sourceThemeID)|\(font.rawValue)|\(lineSpacing)|\(themesRevision)"
    }

    /// Applies theme, fonts and spacing to an editor configuration.
    func apply(to configuration: inout MarkdownEditorConfiguration, highlightsCode: Bool) {
        let theme = self.theme
        let source = self.sourceTheme
        theme.apply(to: &configuration.theme)
        // A font choice overrides the theme's heading font too, so headings match the body.
        if font != .theme { configuration.theme.headingFontName = nil }
        source.apply(to: &configuration.source)
        if configuration.renderingMode == .source, source.id != theme.id {
            // The source view's own theme: its background and link color.
            var sourceTheme = configuration.theme
            source.apply(to: &sourceTheme)
            configuration.theme.background = sourceTheme.background
            configuration.theme.link = sourceTheme.link
            configuration.theme.mutedText = sourceTheme.mutedText
            configuration.theme.selection = sourceTheme.selection
            configuration.theme.caret = sourceTheme.caret
        }
        // Extra leading on top of the natural line height.
        configuration.paragraph.lineHeightExtraSpacing += ((lineSpacing - 1) * fontSize).rounded()
        if highlightsCode {
            let codeTheme = configuration.renderingMode == .source ? source : theme
            configuration.services.syntaxHighlighter = Self.highlighter(for: codeTheme)
        }
        configuration.appearanceRevision = revision
    }

    // MARK: Code highlighting

    /// One bridge per code theme + background; each holds a JavaScriptCore context, so they're kept.
    private static var highlighters: [String: HighlighterSwiftBridge] = [:]

    static func highlighter(for theme: EditorTheme) -> HighlighterSwiftBridge {
        let code = theme.codeTheme ?? EditorTheme.CodeTheme(light: "atom-one-light", dark: "atom-one-dark")
        let backgrounds = theme.codeBackgrounds
        let key = "\(code.light)|\(code.dark)|\(theme.light.codeBackground ?? "")|\(theme.dark.codeBackground ?? "")"
        if let cached = highlighters[key] { return cached }
        let bridge: HighlighterSwiftBridge
        if let backgrounds {
            bridge = HighlighterSwiftBridge(lightTheme: code.light, darkTheme: code.dark,
                                            lightBackground: backgrounds.light, darkBackground: backgrounds.dark)
        } else {
            bridge = HighlighterSwiftBridge(lightTheme: code.light, darkTheme: code.dark)
        }
        highlighters[key] = bridge
        return bridge
    }
}
