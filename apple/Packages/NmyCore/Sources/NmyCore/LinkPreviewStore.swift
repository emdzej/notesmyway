//
//  LinkPreviewStore.swift
//  NmyCore
//
//  Data for link preview cards (spec §4.4). Lookups are synchronous, as the
//  editor's `LinkPreviewProvider` needs: a miss returns `.loading` and starts
//  a fetch; when it finishes `version` changes and `onChange` fires so the
//  editor restyles. Sources:
//  - web pages: the page's OpenGraph / meta tags (one GET), cached in the
//    index's `link_previews` table and an image folder, refreshed after 7 days;
//  - notes: title, snippet, first image (from the index, or the file itself
//    for standalone notes);
//  - other files: a QuickLook thumbnail, file kind and size.
//  Only links the editor asks about are fetched; nothing is crawled.
//

import CryptoKit
import Foundation
import GRDB
import ImageIO
import QuickLookThumbnailing
import Synchronization
import UniformTypeIdentifiers

public struct LinkPreviewData: Equatable, Sendable {
    public enum Status: String, Sendable { case loading, ready, unavailable }

    public var status: Status
    public var title: String?
    public var summary: String?
    /// Host name, or file kind and size ("PDF Document · 2.4 MB").
    public var subtitle: String?
    /// Local copies of the icon and hero / thumbnail image.
    public var iconURL: URL?
    public var imageURL: URL?

    public static let loading = LinkPreviewData(status: .loading)
    public static let unavailable = LinkPreviewData(status: .unavailable)
}

public final class LinkPreviewStore: Sendable {

    public struct Options: Sendable {
        /// Fetch web pages at all (the notebook's "web previews" setting).
        public var allowsNetwork = true
        public var maxAge: TimeInterval = 7 * 24 * 3600
        public var timeout: TimeInterval = 10
        public var thumbnailSize = CGSize(width: 320, height: 320)
        public init() {}
    }

    private struct Entry {
        var data: LinkPreviewData
        var fetched: Date
        var stamp: String?   // files: size + mtime, so edits invalidate
    }

    private let cacheFolder: URL
    private let index: NotebookIndex?
    private let session: URLSession
    private let options: Options
    private let onChange: @Sendable () -> Void
    private let state = Mutex<(entries: [String: Entry], loading: Set<String>, version: Int)>(([:], [], 0))

    /// - Parameters:
    ///   - cacheFolder: where downloaded images and thumbnails go (derived, deletable).
    ///   - index: persists web previews and answers note previews; nil for standalone files.
    ///   - onChange: called (on any thread) after a preview finished loading.
    public init(cacheFolder: URL, index: NotebookIndex?, session: URLSession = .shared,
                options: Options = Options(), onChange: @escaping @Sendable () -> Void = {}) {
        self.cacheFolder = cacheFolder
        self.index = index
        self.session = session
        self.options = options
        self.onChange = onChange
    }

    /// Changes whenever a preview finishes loading (the editor's fingerprint).
    public var version: Int { state.withLock { $0.version } }

    /// The preview for `target`; `.loading` (or the stale value) while a fetch runs,
    /// nil for targets that never get previews (anchors, web with networking off).
    public func preview(for target: LinkTarget) -> LinkPreviewData? {
        guard let key = Self.key(for: target) else { return nil }
        if case .external = target, !options.allowsNetwork { return nil }
        let stamp = Self.stamp(for: target)
        let now = Date()
        let (hit, shouldLoad) = state.withLock { state -> (LinkPreviewData?, Bool) in
            let entry = state.entries[key]
            let fresh = entry.map { $0.stamp == stamp && now.timeIntervalSince($0.fetched) < options.maxAge } ?? false
            if fresh { return (entry!.data, false) }
            let start = state.loading.insert(key).inserted
            return (entry?.data, start)
        }
        if shouldLoad {
            Task.detached(priority: .utility) { [self] in
                let data = await load(target, key: key)
                state.withLock { state in
                    state.entries[key] = Entry(data: data, fetched: Date(), stamp: stamp)
                    state.loading.remove(key)
                    state.version += 1
                }
                onChange()
            }
        }
        return hit ?? .loading
    }

    /// Forgets `target` (and its stored row) so the next lookup refetches.
    public func refresh(_ target: LinkTarget) {
        guard let key = Self.key(for: target) else { return }
        state.withLock { state in
            state.entries[key] = nil
            state.version += 1
        }
        try? index?.deletePreview(url: key)
        onChange()
    }

    /// Waits until no fetch is running (tests, shutdown).
    public func idle() async {
        while state.withLock({ !$0.loading.isEmpty }) { try? await Task.sleep(for: .milliseconds(20)) }
    }

    // MARK: Loading

    private func load(_ target: LinkTarget, key: String) async -> LinkPreviewData {
        switch target {
        case .anchor: return .unavailable
        case .external(let url): return await loadWeb(url, key: key)
        case .file(let url, _): return await loadFile(url)
        }
    }

    private func loadWeb(_ url: URL, key: String) async -> LinkPreviewData {
        if let stored = try? index?.storedPreview(url: key), Date().timeIntervalSince(stored.fetched) < options.maxAge {
            return stored.data
        }
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return .unavailable }
        var request = URLRequest(url: url, timeoutInterval: options.timeout)
        request.setValue("text/html,application/xhtml+xml;q=0.9,*/*;q=0.5", forHTTPHeaderField: "Accept")
        let data: LinkPreviewData
        do {
            let (body, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse
            guard (200..<300).contains(http?.statusCode ?? 200) else { throw URLError(.badServerResponse) }
            let finalURL = response.url ?? url
            let mime = response.mimeType?.lowercased() ?? ""
            let host = Self.host(of: finalURL)
            if mime.hasPrefix("image/") {
                data = LinkPreviewData(status: .ready, title: finalURL.lastPathComponent, subtitle: host,
                                       imageURL: try? saveImage(body, for: finalURL))
            } else if mime.contains("html") || mime.isEmpty {
                let html = String(decoding: body.prefix(1_000_000), as: UTF8.self)
                let meta = HTMLMetadata(html: html, baseURL: finalURL)
                async let image = download(meta.imageURL)
                async let icon = download(meta.iconURL)
                data = LinkPreviewData(status: .ready, title: meta.title ?? host, summary: meta.summary,
                                       subtitle: meta.siteName ?? host, iconURL: await icon, imageURL: await image)
            } else {
                data = LinkPreviewData(status: .ready, title: finalURL.lastPathComponent, subtitle: host)
            }
        } catch {
            data = .unavailable
        }
        try? index?.storePreview(url: key, data: data, fetched: Date())
        return data
    }

    private func download(_ url: URL?) async -> URL? {
        guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        guard let (body, response) = try? await session.data(for: URLRequest(url: url, timeoutInterval: options.timeout)),
              (200..<300).contains((response as? HTTPURLResponse)?.statusCode ?? 200),
              response.mimeType?.lowercased().hasPrefix("image/") ?? true, !body.isEmpty else { return nil }
        return try? saveImage(body, for: url)
    }

    private func saveImage(_ data: Data, for url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
        let ext = url.pathExtension.isEmpty || url.pathExtension.count > 5 ? "img" : url.pathExtension.lowercased()
        let file = cacheFolder.appending(path: Self.digest(url.absoluteString) + "." + ext)
        try data.write(to: file, options: .atomic)
        return file
    }

    private func loadFile(_ url: URL) async -> LinkPreviewData {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentTypeKey])
        guard values?.isRegularFile == true else { return .unavailable }

        if FileKind.noteExtensions.contains(url.pathExtension.lowercased()) {
            var title: String
            var summary: String?
            var firstImage: String?
            if let index, let path = index.notebook.path(for: url), let note = try? index.note(at: path) {
                (title, summary, firstImage) = (note.title, note.snippet, note.firstImage)
            } else if let text = try? NoteFile(url: url).read().text {
                let metadata = NoteMetadata(markdown: text, fileName: url.deletingPathExtension().lastPathComponent)
                (title, summary, firstImage) = (metadata.title, metadata.snippet, metadata.firstImage)
            } else {
                return .unavailable
            }
            if summary?.isEmpty == true { summary = nil }
            var image: URL?
            if let firstImage, case .file(let imageURL, _)? = LinkTarget.resolve(firstImage, from: url, root: index?.notebook.root) {
                image = await thumbnail(for: imageURL)
            }
            if title.isEmpty { title = url.deletingPathExtension().lastPathComponent }
            return LinkPreviewData(status: .ready, title: title, summary: summary, subtitle: "Note", imageURL: image)
        }

        let kind = values?.contentType?.localizedDescription ?? url.pathExtension.uppercased()
        let size = ByteCountFormatter.string(fromByteCount: Int64(values?.fileSize ?? 0), countStyle: .file)
        return LinkPreviewData(status: .ready, title: url.lastPathComponent, subtitle: "\(kind) · \(size)",
                               imageURL: await thumbnail(for: url))
    }

    /// A PNG thumbnail of a local file in the cache folder, nil if QuickLook can't make one.
    private func thumbnail(for url: URL) async -> URL? {
        let stamp = Self.stamp(for: .file(url, fragment: nil)) ?? ""
        let file = cacheFolder.appending(path: Self.digest(url.path + stamp) + ".png")
        if FileManager.default.fileExists(atPath: file.path) { return file }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: options.thumbnailSize, scale: 2, representationTypes: .thumbnail)
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request),
              let png = Self.png(representation.cgImage) else { return nil }
        try? FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
        return (try? png.write(to: file, options: .atomic)) != nil ? file : nil
    }

    // MARK: Helpers

    static func key(for target: LinkTarget) -> String? {
        switch target {
        case .anchor: return nil
        case .external(let url): return url.absoluteString
        case .file(let url, _): return url.standardizedFileURL.path
        }
    }

    static func stamp(for target: LinkTarget) -> String? {
        guard case .file(let fileURL, _) = target else { return nil }
        var url = fileURL
        url.removeAllCachedResourceValues()
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return "\(values?.fileSize ?? -1)-\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
    }

    static func host(of url: URL) -> String? {
        guard let host = url.host() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func digest(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}

// MARK: - Persistence (link_previews table)

extension NotebookIndex {
    func storedPreview(url: String) throws -> (data: LinkPreviewData, fetched: Date)? {
        try db.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM link_previews WHERE url = ?", arguments: [url]) else { return nil }
            let fetched: Int64 = row["fetched"] ?? 0
            let icon: String? = row["icon_path"]
            let image: String? = row["image_path"]
            // Cached images may have been cleared; a missing file just drops the picture.
            func existing(_ path: String?) -> URL? {
                guard let path, FileManager.default.fileExists(atPath: path) else { return nil }
                return URL(fileURLWithPath: path)
            }
            let data = LinkPreviewData(
                status: LinkPreviewData.Status(rawValue: row["status"] ?? "") ?? .unavailable,
                title: row["title"], summary: row["summary"], subtitle: row["subtitle"],
                iconURL: existing(icon), imageURL: existing(image)
            )
            return (data, Date(timeIntervalSince1970: Double(fetched) / 1000))
        }
    }

    func storePreview(url: String, data: LinkPreviewData, fetched: Date) throws {
        try db.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO link_previews (url, title, summary, subtitle, icon_path, image_path, fetched, status)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [url, data.title, data.summary, data.subtitle, data.iconURL?.path, data.imageURL?.path,
                                 Int64(fetched.timeIntervalSince1970 * 1000), data.status.rawValue])
        }
    }

    func deletePreview(url: String) throws {
        try db.write { db in try db.execute(sql: "DELETE FROM link_previews WHERE url = ?", arguments: [url]) }
    }
}
