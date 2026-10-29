//
//  NotebookPath.swift
//  NmyCore
//
//  A file's path relative to its notebook root: `/`-separated, NFC-normalized,
//  no leading slash, never escaping the root. This is the key the index
//  stores and the form links resolve to.
//

import Foundation

public struct NotebookPath: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let rawValue: String

    /// Normalizes `path`: NFC, `.` and empty components dropped, `..` applied.
    /// Nil if it is empty or climbs above the root.
    public init?(_ path: String) {
        var parts: [Substring] = []
        for component in path.precomposedStringWithCanonicalMapping.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".": continue
            case "..":
                guard !parts.isEmpty else { return nil }
                parts.removeLast()
            default: parts.append(component)
            }
        }
        guard !parts.isEmpty else { return nil }
        rawValue = parts.joined(separator: "/")
    }

    /// The path of `url` inside `root`, or nil if it lies outside.
    public init?(url: URL, root: URL) {
        let rootComponents = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let components = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard components.count > rootComponents.count,
              Array(components.prefix(rootComponents.count)) == rootComponents else { return nil }
        self.init(components.dropFirst(rootComponents.count).joined(separator: "/"))
    }

    public var description: String { rawValue }

    public static func < (lhs: NotebookPath, rhs: NotebookPath) -> Bool {
        lhs.rawValue.localizedStandardCompare(rhs.rawValue) == .orderedAscending
    }

    public var components: [String] { rawValue.components(separatedBy: "/") }

    /// Last component, with extension.
    public var name: String { components.last ?? rawValue }

    /// Last component without its extension.
    public var stem: String { (name as NSString).deletingPathExtension }

    /// Lowercased extension, without the dot.
    public var pathExtension: String { (name as NSString).pathExtension.lowercased() }

    /// The containing folder, or nil at the notebook root.
    public var parent: NotebookPath? {
        let parts = components
        return parts.count > 1 ? NotebookPath(parts.dropLast().joined(separator: "/")) : nil
    }

    public func appending(_ component: String) -> NotebookPath? {
        NotebookPath(rawValue + "/" + component)
    }

    public func url(in root: URL) -> URL {
        root.appending(path: rawValue, directoryHint: .notDirectory)
    }
}
