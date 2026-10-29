//
//  LinkTarget.swift
//  NmyCore
//
//  What a markdown link destination points at. Resolution works on file
//  URLs, so it is the same for a note in a notebook and a standalone file:
//  relative destinations resolve against the folder of the note.
//

import Foundation

public enum LinkTarget: Equatable, Sendable {
    /// `https:`, `mailto:`, … : anything with a URL scheme.
    case external(URL)
    /// `#heading` in the same note.
    case anchor(String)
    /// A local file, with an optional `#fragment`.
    case file(URL, fragment: String?)

    /// Resolves `destination` as written in the note at `noteURL`.
    /// `/`-prefixed paths are relative to `root` (the notebook) when given.
    public static func resolve(_ destination: String, from noteURL: URL, root: URL? = nil) -> LinkTarget? {
        var raw = destination.trimmingCharacters(in: .whitespaces)
        if raw.hasPrefix("<"), raw.hasSuffix(">") { raw = String(raw.dropFirst().dropLast()) }
        guard !raw.isEmpty else { return nil }
        if raw.hasPrefix("#") { return .anchor(String(raw.dropFirst()).removingPercentEncoding ?? String(raw.dropFirst())) }
        if hasScheme(raw) { return URL(string: raw).map(LinkTarget.external) }

        var path = raw
        var fragment: String?
        if let hash = raw.firstIndex(of: "#") {
            path = String(raw[..<hash])
            fragment = String(raw[raw.index(after: hash)...])
        }
        if let query = path.firstIndex(of: "?") { path = String(path[..<query]) }
        let decoded = path.removingPercentEncoding ?? path
        let base = decoded.hasPrefix("/") ? (root ?? noteURL.deletingLastPathComponent()) : noteURL.deletingLastPathComponent()
        let relative = decoded.hasPrefix("/") ? String(decoded.drop(while: { $0 == "/" })) : decoded
        let url = base.appending(path: relative, directoryHint: .notDirectory).standardizedFileURL
        return .file(url, fragment: fragment?.removingPercentEncoding ?? fragment)
    }

    /// `scheme:` per RFC 3986; a Windows drive letter (`C:`) doesn't count.
    static func hasScheme(_ s: String) -> Bool {
        guard let colon = s.firstIndex(of: ":"), colon != s.startIndex else { return false }
        let scheme = s[..<colon]
        guard scheme.count > 1, let first = scheme.first, first.isASCII, first.isLetter else { return false }
        return scheme.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == ".") }
    }
}
