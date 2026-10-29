//
//  FolderGrants.swift
//  NmwUI
//
//  Opening a standalone file grants the sandbox access to that file only.
//  Showing its sibling images and storing dropped files needs the folder,
//  which the user grants once (spec §3.4); the grant is kept as a bookmark
//  and covers every file below that folder.
//

import Foundation
#if os(macOS)
import AppKit
#endif

@MainActor
enum FolderGrants {
    private static let key = "nmw.folderGrants"

    /// True when the folder can be listed (granted, or no sandbox).
    static func isAccessible(_ folder: URL) -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) != nil
    }

    /// Starts access for a remembered grant covering `folder`; true if the
    /// folder is accessible afterwards.
    @discardableResult
    static func restore(covering folder: URL, defaults: UserDefaults = .standard) -> Bool {
        if isAccessible(folder) { return true }
        for data in defaults.array(forKey: key) as? [Data] ?? [] {
            guard let url = resolve(data), contains(url, folder) else { continue }
            _ = url.startAccessingSecurityScopedResource()
            if isAccessible(folder) { return true }
        }
        return false
    }

    /// Remembers a folder the user granted (already being accessed).
    static func remember(_ folder: URL, defaults: UserDefaults = .standard) {
        _ = folder.startAccessingSecurityScopedResource()
        #if os(macOS)
        let options: URL.BookmarkCreationOptions = .withSecurityScope
        #else
        let options: URL.BookmarkCreationOptions = []
        #endif
        guard let data = try? folder.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        var all = defaults.array(forKey: key) as? [Data] ?? []
        all.append(data)
        defaults.set(Array(all.suffix(50)), forKey: key)
    }

    #if os(macOS)
    /// Asks for `folder` with an open panel starting there; true once granted.
    static func request(_ folder: URL) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        panel.prompt = "Allow"
        panel.message = "Notes my Way needs this folder to show the note’s images and save files you drop into it."
        guard panel.runModal() == .OK, let url = panel.url, contains(url, folder) else { return false }
        remember(url)
        return isAccessible(folder)
    }
    #endif

    private static func contains(_ ancestor: URL, _ folder: URL) -> Bool {
        let a = ancestor.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let f = folder.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        return f.count >= a.count && Array(f.prefix(a.count)) == a
    }

    private static func resolve(_ data: Data) -> URL? {
        var stale = false
        #if os(macOS)
        return try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
        #else
        return try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        #endif
    }
}
