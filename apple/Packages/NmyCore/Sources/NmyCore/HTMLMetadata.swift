//
//  HTMLMetadata.swift
//  NmyCore
//
//  Title, description, image and icon of a web page, from its OpenGraph /
//  Twitter / standard `<meta>` and `<link>` tags. Only the `<head>` is read.
//

import Foundation

public struct HTMLMetadata: Equatable, Sendable {
    public var title: String?
    public var summary: String?
    public var siteName: String?
    public var imageURL: URL?
    public var iconURL: URL?

    /// Parses `html` served from `baseURL` (relative URLs resolve against it,
    /// or against `<base href>`).
    public init(html: String, baseURL: URL) {
        let head = Self.head(of: html)
        var meta: [String: String] = [:]
        for tag in Self.tags(named: "meta", in: head) {
            let attributes = Self.attributes(of: tag)
            guard let key = (attributes["property"] ?? attributes["name"] ?? attributes["itemprop"])?.lowercased(),
                  let content = attributes["content"].map(Self.decodeEntities)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !content.isEmpty, meta[key] == nil else { continue }
            meta[key] = content
        }
        var base = baseURL
        if let href = Self.tags(named: "base", in: head).lazy.compactMap({ Self.attributes(of: $0)["href"] }).first,
           let url = URL(string: href, relativeTo: baseURL) {
            base = url.absoluteURL
        }
        func url(_ s: String?) -> URL? {
            guard let s, !s.isEmpty else { return nil }
            return URL(string: Self.decodeEntities(s).trimmingCharacters(in: .whitespaces), relativeTo: base)?.absoluteURL
        }

        title = meta["og:title"] ?? meta["twitter:title"] ?? Self.titleElement(head)
        summary = meta["og:description"] ?? meta["twitter:description"] ?? meta["description"]
        siteName = meta["og:site_name"] ?? meta["application-name"]
        imageURL = url(meta["og:image:secure_url"] ?? meta["og:image"] ?? meta["og:image:url"] ?? meta["twitter:image"] ?? meta["twitter:image:src"])

        // Largest declared icon wins; apple-touch-icon is usually the crispest.
        var icons: [(url: URL, score: Int)] = []
        for tag in Self.tags(named: "link", in: head) {
            let attributes = Self.attributes(of: tag)
            guard let rel = attributes["rel"]?.lowercased(), let href = url(attributes["href"]) else { continue }
            let rels = rel.split(separator: " ")
            guard rels.contains("icon") || rels.contains("apple-touch-icon") || rels.contains("apple-touch-icon-precomposed") else { continue }
            let size = attributes["sizes"].flatMap { Int($0.lowercased().split(separator: "x").first ?? "") } ?? (rels.contains("icon") ? 16 : 180)
            let svgPenalty = href.pathExtension.lowercased() == "svg" ? -1000 : 0   // can't be drawn as a bitmap
            icons.append((href, size + svgPenalty))
        }
        iconURL = icons.max { $0.score < $1.score }?.url ?? URL(string: "/favicon.ico", relativeTo: base)?.absoluteURL
    }

    // MARK: Tag scanning

    static func head(of html: String) -> Substring {
        if let end = html.range(of: "</head>", options: .caseInsensitive) { return html[..<end.lowerBound] }
        return html.prefix(200_000)
    }

    /// Raw `<name …>` tags (the text between `<` and `>`).
    static func tags(named name: String, in html: Substring) -> [Substring] {
        var result: [Substring] = []
        var search = html.startIndex
        let open = "<" + name
        while let start = html.range(of: open, options: .caseInsensitive, range: search..<html.endIndex) {
            guard start.upperBound < html.endIndex else { break }
            let next = html[start.upperBound]
            guard next.isWhitespace || next == ">" || next == "/" else { search = start.upperBound; continue }
            guard let end = html[start.upperBound...].firstIndex(of: ">") else { break }
            result.append(html[start.upperBound..<end])
            search = html.index(after: end)
        }
        return result
    }

    /// Lowercased attribute names → values (quoted or bare).
    static func attributes(of tag: Substring) -> [String: String] {
        var result: [String: String] = [:]
        var i = tag.startIndex
        func skipSpace() { while i < tag.endIndex, tag[i].isWhitespace || tag[i] == "/" { i = tag.index(after: i) } }
        while true {
            skipSpace()
            guard i < tag.endIndex else { break }
            let nameStart = i
            while i < tag.endIndex, !tag[i].isWhitespace, tag[i] != "=", tag[i] != ">" { i = tag.index(after: i) }
            let name = tag[nameStart..<i].lowercased()
            while i < tag.endIndex, tag[i].isWhitespace { i = tag.index(after: i) }
            guard i < tag.endIndex, tag[i] == "=" else {
                if !name.isEmpty { result[name] = result[name] ?? "" }
                continue
            }
            i = tag.index(after: i)
            while i < tag.endIndex, tag[i].isWhitespace { i = tag.index(after: i) }
            guard i < tag.endIndex else { break }
            var value: Substring
            if tag[i] == "\"" || tag[i] == "'" {
                let quote = tag[i]
                let valueStart = tag.index(after: i)
                let valueEnd = tag[valueStart...].firstIndex(of: quote) ?? tag.endIndex
                value = tag[valueStart..<valueEnd]
                i = valueEnd < tag.endIndex ? tag.index(after: valueEnd) : valueEnd
            } else {
                let valueStart = i
                while i < tag.endIndex, !tag[i].isWhitespace { i = tag.index(after: i) }
                value = tag[valueStart..<i]
            }
            if !name.isEmpty, result[name] == nil { result[name] = String(value) }
        }
        return result
    }

    static func titleElement(_ head: Substring) -> String? {
        guard let open = head.range(of: "<title", options: .caseInsensitive),
              let start = head[open.upperBound...].firstIndex(of: ">"),
              let close = head.range(of: "</title>", options: .caseInsensitive, range: start..<head.endIndex) else { return nil }
        let text = decodeEntities(String(head[head.index(after: start)..<close.lowerBound]))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = ""
        var i = s.startIndex
        let named: [String: String] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "#39": "'", "nbsp": "\u{A0}",
                                       "mdash": "—", "ndash": "–", "hellip": "…", "rsquo": "’", "lsquo": "‘", "rdquo": "”", "ldquo": "“"]
        while i < s.endIndex {
            if s[i] == "&", let semi = s[i...].prefix(12).firstIndex(of: ";") {
                let entity = String(s[s.index(after: i)..<semi])
                if let replacement = named[entity] {
                    out += replacement; i = s.index(after: semi); continue
                }
                if entity.hasPrefix("#") {
                    let digits = entity.dropFirst()
                    let code = digits.lowercased().hasPrefix("x") ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
                    if let code, let scalar = Unicode.Scalar(code) {
                        out.unicodeScalars.append(scalar); i = s.index(after: semi); continue
                    }
                }
            }
            out.append(s[i])
            i = s.index(after: i)
        }
        return out
    }
}
