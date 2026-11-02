//
//  AppLanguage.swift
//  NmwUI
//
//  The app's language: the system's by default, or English or Polish
//  chosen in Settings › General. The choice is the app's own
//  `AppleLanguages`, the same setting iOS's Settings › Apps › Language
//  writes, so it takes effect the next time the app starts.
//

import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case polish = "pl"

    var id: String { rawValue }

    /// Languages are named in themselves, as in the system's own lists.
    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .english: "English"
        case .polish: "Polski"
        }
    }

    private static let key = "AppleLanguages"

    /// The language chosen for this app (not the system's list, which
    /// `UserDefaults.standard` also returns when there's no choice).
    static func current(_ defaults: UserDefaults = .standard) -> AppLanguage {
        guard let id = Bundle.main.bundleIdentifier,
              let languages = defaults.persistentDomain(forName: id)?[key] as? [String],
              let first = languages.first else { return .system }
        return first.hasPrefix("pl") ? .polish : first.hasPrefix("en") ? .english : .system
    }

    func apply(_ defaults: UserDefaults = .standard) {
        if self == .system { defaults.removeObject(forKey: Self.key) } else { defaults.set([rawValue], forKey: Self.key) }
    }

    /// The language the app is showing now.
    static var running: AppLanguage {
        Bundle.main.preferredLocalizations.first?.hasPrefix("pl") == true ? .polish : .english
    }
}
