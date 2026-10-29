//
//  NotebookConfig.swift
//  NmwCore
//
//  Per-notebook settings in `.nmw/config.json` (spec §3.1). The file lives
//  in the notebook, so it syncs with it. Keys this version doesn't know are
//  kept when saving, and missing keys fall back to defaults.
//

import Foundation

public struct NotebookConfig: Equatable, Sendable {

    public enum AttachmentPlacement: String, CaseIterable, Sendable {
        /// `<note's folder>/<folder name>/`
        case nextToNote
        /// `<notebook root>/<folder name>/<note name>/`
        case notebookRoot
    }

    public struct Attachments: Equatable, Sendable {
        public var folderName: String
        public var placement: AttachmentPlacement
        /// Show attachment folders in the sidebar's folder tree.
        public var showInSidebar: Bool

        public init(folderName: String = ".attachments", placement: AttachmentPlacement = .nextToNote, showInSidebar: Bool = false) {
            self.folderName = folderName
            self.placement = placement
            self.showInSidebar = showInSidebar
        }

        /// A folder name nmw can use: no path separators, not `.` / `..`.
        public static func isValidFolderName(_ name: String) -> Bool {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && trimmed != "." && trimmed != ".." && !trimmed.contains("/") && !trimmed.contains(":")
        }
    }

    public var attachments: Attachments
    /// Fetch previews for web links marked `{.preview}`.
    public var webPreviews: Bool
    /// Rename a note's file to match its first heading (default off).
    public var renameFilesToTitle: Bool

    public init(attachments: Attachments = Attachments(), webPreviews: Bool = true, renameFilesToTitle: Bool = false) {
        self.attachments = attachments
        self.webPreviews = webPreviews
        self.renameFilesToTitle = renameFilesToTitle
    }

    public static func url(for notebook: Notebook) -> URL {
        notebook.root.appending(path: ".nmw/config.json", directoryHint: .notDirectory)
    }

    /// The notebook's settings, or defaults when there's no (readable) file.
    public static func load(for notebook: Notebook) -> NotebookConfig {
        var config = NotebookConfig()
        guard let data = try? Data(contentsOf: url(for: notebook)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return config }
        if let a = json["attachments"] as? [String: Any] {
            if let name = a["folderName"] as? String, Attachments.isValidFolderName(name) { config.attachments.folderName = name }
            if let raw = a["placement"] as? String, let placement = AttachmentPlacement(rawValue: raw) { config.attachments.placement = placement }
            if let show = a["showInSidebar"] as? Bool { config.attachments.showInSidebar = show }
        }
        if let web = json["webPreviews"] as? Bool { config.webPreviews = web }
        if let rename = json["renameFilesToTitle"] as? Bool { config.renameFilesToTitle = rename }
        return config
    }

    /// Writes the settings, keeping any keys this version doesn't know.
    public func save(for notebook: Notebook) throws {
        let url = Self.url(for: notebook)
        var json = (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        var a = json["attachments"] as? [String: Any] ?? [:]
        a["folderName"] = attachments.folderName
        a["placement"] = attachments.placement.rawValue
        a["showInSidebar"] = attachments.showInSidebar
        json["attachments"] = a
        json["webPreviews"] = webPreviews
        json["renameFilesToTitle"] = renameFilesToTitle
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try NoteFile(url: url).write(String(decoding: data, as: UTF8.self) + "\n", replacing: nil)
    }
}
