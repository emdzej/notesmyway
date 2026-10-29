//
//  ShareJob.swift
//  NmwShared
//
//  Content shared into Notes my Way from another app. The share extension
//  can't write into notebooks (their folder access belongs to the app), so
//  it queues a job, `Inbox/<id>/job.json` plus copies of shared images, and
//  the app imports it the next time it's active.
//

import Foundation

public struct ShareJob: Codable, Equatable, Sendable, Identifiable {

    public enum Destination: String, Codable, Sendable, CaseIterable {
        /// A new note at the notebook's top level.
        case newNote
        /// Appended to `Inbox.md` at the notebook's top level.
        case inbox
    }

    public enum Item: Codable, Equatable, Sendable {
        case text(String)
        case url(URL, title: String?)
        /// A file in the job's folder.
        case image(fileName: String)
    }

    public var id: UUID
    public var created: Date
    /// nil: the notebook selected in the app.
    public var notebookID: String?
    public var destination: Destination
    public var title: String?
    public var comment: String?
    public var items: [Item]

    public init(id: UUID = UUID(), created: Date = Date(), notebookID: String?, destination: Destination,
                title: String? = nil, comment: String? = nil, items: [Item]) {
        self.id = id
        self.created = created
        self.notebookID = notebookID
        self.destination = destination
        self.title = title
        self.comment = comment
        self.items = items
    }

    /// A job's folder in the inbox: `job.json` and its images.
    public struct Folder: Sendable {
        public let url: URL
        public var jobURL: URL { url.appending(path: "job.json", directoryHint: .notDirectory) }
        public func file(_ name: String) -> URL { url.appending(path: name, directoryHint: .notDirectory) }
    }

    /// Creates the job's folder (images are copied in with `addFile`) and
    /// returns it; call `commit(to:)` once the files are in place.
    public static func makeFolder(in inbox: URL = AppGroup.inboxFolder, id: UUID) throws -> Folder {
        let url = inbox.appending(path: id.uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return Folder(url: url)
    }

    /// Writes `job.json` last, so the app never sees a half-written job.
    public func commit(to folder: Folder) throws {
        try JSONEncoder().encode(self).write(to: folder.jobURL, options: .atomic)
    }

    /// Jobs waiting in the inbox, oldest first.
    public static func pending(in inbox: URL = AppGroup.inboxFolder) -> [(job: ShareJob, folder: Folder)] {
        let decoder = JSONDecoder()
        let folders = (try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { url in
            let folder = Folder(url: url)
            guard let data = try? Data(contentsOf: folder.jobURL),
                  let job = try? decoder.decode(ShareJob.self, from: data) else { return nil }
            return (job, folder)
        }
        .sorted { $0.job.created < $1.job.created }
    }
}
