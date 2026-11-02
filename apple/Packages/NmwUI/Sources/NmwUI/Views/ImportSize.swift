//
//  ImportSize.swift
//  NmwUI
//
//  What the import sheets (Apple Notes, Obsidian) say about how much an
//  import writes, and where it goes.
//

import Foundation

enum ImportSize {
    /// "12.3 MB", as Finder counts.
    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// A warning when the notebook's disk has less room than the import needs.
    static func spaceWarning(_ bytes: Int64, at folder: URL) -> String? {
        guard let free = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage, free > 0, free < bytes else { return nil }
        return "Only \(format(free)) is free on the notebook’s disk."
    }

    /// `name` in `root`, or "name 2", "name 3", … if that folder is already there.
    static func uniqueFolder(named name: String, in root: URL) -> URL {
        var candidate = root.appending(path: name, directoryHint: .isDirectory)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = root.appending(path: "\(name) \(n)", directoryHint: .isDirectory)
            n += 1
        }
        return candidate
    }
}
