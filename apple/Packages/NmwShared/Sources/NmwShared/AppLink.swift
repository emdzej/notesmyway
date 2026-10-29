//
//  AppLink.swift
//  NmwShared
//
//  `notesmyway://` links, used by widgets, Shortcuts and Spotlight:
//  `notesmyway://open?notebook=<id>&path=<path>` and
//  `notesmyway://new?notebook=<id>&folder=<path>&text=<markdown>`
//  (every `new` parameter is optional).
//

import Foundation

public enum AppLink: Equatable, Sendable {
    case open(notebook: String, path: String)
    case new(notebook: String? = nil, folder: String? = nil, text: String? = nil)

    public static let scheme = "notesmyway"

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .open(let notebook, let path):
            components.host = "open"
            components.queryItems = [URLQueryItem(name: "notebook", value: notebook), URLQueryItem(name: "path", value: path)]
        case .new(let notebook, let folder, let text):
            components.host = "new"
            let items = [("notebook", notebook), ("folder", folder), ("text", text)]
                .compactMap { name, value in value.map { URLQueryItem(name: name, value: $0) } }
            components.queryItems = items.isEmpty ? nil : items
        }
        return components.url!
    }

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        func value(_ name: String) -> String? {
            components.queryItems?.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }
        switch components.host?.lowercased() {
        case "open":
            guard let notebook = value("notebook"), let path = value("path") else { return nil }
            self = .open(notebook: notebook, path: path)
        case "new":
            self = .new(notebook: value("notebook"), folder: value("folder"), text: value("text"))
        default:
            return nil
        }
    }
}
