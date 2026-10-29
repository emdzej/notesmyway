//
//  Palette.swift
//  NmwUI
//
//  The app's accent: the blue-teal of the icon. Matches `AccentColor` in the
//  app's asset catalog; defined here too so the editor's links use it.
//

#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI
import MarkdownEngine

enum Palette {
    /// `#0B6E8E` in light mode, `#3AB7CF` in dark mode.
    static let accent: PlatformColor = {
        let light = PlatformColor(red: 0x0B / 255, green: 0x6E / 255, blue: 0x8E / 255, alpha: 1)
        let dark = PlatformColor(red: 0x3A / 255, green: 0xB7 / 255, blue: 0xCF / 255, alpha: 1)
        #if os(macOS)
        return NSColor(name: "nmwAccent") { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
        #else
        return UIColor { $0.userInterfaceStyle == .dark ? dark : light }
        #endif
    }()

    static var accentColor: Color { Color(accent) }
}
