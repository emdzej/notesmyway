//
//  Palette.swift
//  NmwUI
//
//  The app's accent (the icon's teal, lightened) and the app-wide look
//  settings: appearance (system / light / dark) and sidebar style. The
//  accent matches `AccentColor` in the app's asset catalog; a theme's
//  accent or link color replaces it app-wide (`accentColor`).
//

#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI
import MarkdownEngine

enum Palette {
    /// `#1A8FA8` in light mode, `#5CCFDB` in dark mode.
    static let accent: PlatformColor = dynamic(light: (0x1A, 0x8F, 0xA8), dark: (0x5C, 0xCF, 0xDB), name: "nmwAccent")

    /// The accent in use: the current theme's (its accent or link color), else `accent`.
    @MainActor static var accentColor: Color { Color(EditorAppearance.shared.accent) }

    /// The "My Way" sidebar: the icon's gradient, teal at the top to deep blue.
    static let sidebarTop = Color(red: 0x14 / 255, green: 0x80 / 255, blue: 0x93 / 255)
    static let sidebarBottom = Color(red: 0x0A / 255, green: 0x34 / 255, blue: 0x5C / 255)

    private static func dynamic(light: (Int, Int, Int), dark: (Int, Int, Int), name: String) -> PlatformColor {
        func color(_ c: (Int, Int, Int)) -> PlatformColor {
            PlatformColor(red: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255, blue: CGFloat(c.2) / 255, alpha: 1)
        }
        #if os(macOS)
        return NSColor(name: name) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? color(dark) : color(light)
        }
        #else
        return UIColor { $0.userInterfaceStyle == .dark ? color(dark) : color(light) }
        #endif
    }
}

/// Light, dark, or following the system. Stored in `nmw.appearance`.
public enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    public var id: String { rawValue }
    static let key = "nmw.appearance"

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// The sidebar's background: the theme's (its gradient, else a wash of its
/// page color), the platform's, or the icon's colors. Stored in `nmw.sidebarStyle`.
public enum SidebarStyle: String, CaseIterable, Identifiable, Sendable {
    case theme, system, myWay
    public var id: String { rawValue }
    static let key = "nmw.sidebarStyle"

    var title: String {
        switch self {
        case .theme: "From Theme"
        case .system: "System Default"
        case .myWay: "My Way"
        }
    }
}

/// The theme sets the accent; a light- or dark-only theme also fixes the
/// scheme, over the Appearance setting.
struct AppLook: ViewModifier {
    @AppStorage(AppAppearance.key) private var appearance = AppAppearance.system
    private var theme = EditorAppearance.shared

    private var scheme: ColorScheme? { theme.theme.requiredScheme ?? appearance.colorScheme }

    func body(content: Content) -> some View {
        content
            .tint(Palette.accentColor)
            #if os(macOS)
            // NSApp.appearance, not preferredColorScheme: going back to "System"
            // from a forced scheme doesn't take with the latter on macOS.
            .onChange(of: scheme, initial: true) { _, value in
                NSApp.appearance = switch value {
                case nil: nil
                case .light: NSAppearance(named: .aqua)
                case .dark: NSAppearance(named: .darkAqua)
                @unknown default: nil
                }
            }
            #else
            .preferredColorScheme(scheme)
            #endif
    }
}

extension View {
    func appLook() -> some View { modifier(AppLook()) }
}

/// How notes open: formatted (markdown blended with rendering) or as
/// highlighted markdown source. Stored in `nmw.editorMode`.
public enum EditorMode: String, CaseIterable, Identifiable, Sendable {
    case formatted, source
    public var id: String { rawValue }
    static let key = "nmw.editorMode"

    var title: String {
        switch self {
        case .formatted: "Formatted"
        case .source: "Markdown Source"
        }
    }
}

enum ChecklistSettings {
    /// Checking an item moves it below the unchecked ones (Notes' "Sort Checked Items").
    static let movesCheckedKey = "nmw.movesCheckedToBottom"
}
