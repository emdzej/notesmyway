//
//  SupportDesk.swift
//  NmwUI
//
//  Report a Problem: an anonymous support desk (ALIAS, help.getalias.support).
//  The user writes what happened and may add a screenshot of the window, which
//  they can black out first; support's answers show in the same sheet. No
//  account: the service makes an anonymous id for the install, kept in the
//  Keychain. Only counts and states go with a report, never notes or names.
//  Builds without a product key (App/Secrets.xcconfig) don't show it.
//

import AliasSupport
import CoreGraphics
import Foundation
import os
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
enum SupportDesk {
    static let url = URL(string: "https://help.getalias.support")!

    /// nil without a product key: Report a Problem isn't shown.
    static let client: AliasClient? = {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "NmwAliasKey") as? String,
              !key.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return AliasClient(url: url, key: key, store: identityStore,
                           appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                           context: { context.withLock { $0 } },
                           telemetry: { nil })
    }()

    static var isAvailable: Bool { client != nil }

    /// What goes with the next report, set when the sheet opens (the client asks off the main actor).
    nonisolated private static let context = OSAllocatedUnfairLock<JSONObject>(initialState: [:])

    #if os(macOS)
    /// The data protection keychain when the build is signed for it (Developer ID); an ad hoc
    /// build can't use it, and the login keychain would ask for access after every rebuild, so
    /// those keep the identity in a file in the app's sandbox instead.
    private static let identityStore = FallbackIdentityStore(
        first: KeychainIdentityStore(account: "notesmyway"),
        file: URL.applicationSupportDirectory.appending(path: "Support/identity.json"))
    #else
    private static let identityStore = KeychainIdentityStore(account: "notesmyway")
    #endif

    /// Opens Report a Problem over `session`'s window.
    static func report(from session: NotebookSession, notebooks: Int) {
        prepare(for: session, notebooks: notebooks)
        session.problemReport = .init(window: captureWindow())
    }

    /// Fills in the context for `session` (the product's fields only: counts and states).
    static func prepare(for session: NotebookSession?, notebooks: Int) {
        var fields: JSONObject = [
            "notebooks": .number(Double(notebooks)),
            "editor": .string(UserDefaults.standard.string(forKey: EditorMode.key) ?? EditorMode.formatted.rawValue),
            "language": .string(AppLanguage.running.rawValue),
        ]
        #if os(macOS)
        fields["platform"] = .string("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        #else
        fields["platform"] = .string("\(UIDevice.current.userInterfaceIdiom == .pad ? "iPadOS" : "iOS") \(UIDevice.current.systemVersion)")
        #endif
        if let session {
            fields["screen"] = .string(screen(of: session))
            if let count = try? session.index.notes(sortedBy: .modified).count { fields["notes"] = .number(Double(count)) }
        }
        let snapshot = fields
        context.withLock { $0 = snapshot }
    }

    /// Where the user was, by kind only (no folder, tag or note names).
    private static func screen(of session: NotebookSession) -> String {
        let list = switch session.scope {
        case .all: "all notes"
        case .pinned: "pinned"
        case .folder(nil): "notebook"
        case .folder: "folder"
        case .tag: "tag"
        case .trash: "recently deleted"
        }
        return session.selection == nil ? list : "\(list), note open"
    }

    /// The front window as it is now, before the sheet covers it.
    static func captureWindow() -> CGImage? {
        #if os(macOS)
        guard let view = (NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible && $0.canBecomeMain })?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.cgImage
        #else
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows).first(where: \.isKeyWindow) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = window.screen.scale
        return UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }.cgImage
        #endif
    }
}

#if os(macOS)
/// `first` (the Keychain) while it works; a file readable only by the app when it doesn't.
struct FallbackIdentityStore: IdentityStore {
    let first: KeychainIdentityStore
    let file: URL

    func load() async throws -> Identity? {
        if let kept = try? first.load() { return kept }
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Identity.self, from: data)
    }

    func save(_ identity: Identity?) async throws {
        if (try? first.save(identity)) != nil {
            try? FileManager.default.removeItem(at: file)
            return
        }
        guard let identity else { try? FileManager.default.removeItem(at: file); return }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(identity).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
#endif
