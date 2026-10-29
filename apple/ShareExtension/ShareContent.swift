//
//  ShareContent.swift
//  NmwShare
//
//  Reads what the host app shared (text, web links, images) into a draft
//  share job. Image files are copied right away: a provider's file URL is
//  only valid inside its callback.
//

import Foundation
import NmwShared
import UniformTypeIdentifiers

struct SharedImage: Sendable {
    let url: URL
    let name: String
}

struct ShareContent: Sendable {
    var texts: [String] = []
    var links: [(url: URL, title: String?)] = []
    var images: [SharedImage] = []
    /// Scratch folder holding the image copies until the job is saved.
    let scratch: URL

    static let maxImages = 5

    var isEmpty: Bool { texts.isEmpty && links.isEmpty && images.isEmpty }

    var summary: String {
        var parts: [String] = []
        if let link = links.first { parts.append(link.title ?? link.url.host() ?? link.url.absoluteString) }
        if let text = texts.first { parts.append(String(text.prefix(80))) }
        if !images.isEmpty { parts.append(images.count == 1 ? "1 image" : "\(images.count) images") }
        return parts.joined(separator: " · ")
    }

    var suggestedTitle: String {
        links.first?.title ?? texts.first.flatMap { $0.split(whereSeparator: \.isNewline).first.map(String.init) } ?? ""
    }

    @MainActor
    static func load(from items: [NSExtensionItem]) async -> ShareContent {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "nmw-share-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        var content = ShareContent(scratch: scratch)
        for item in items {
            let itemTitle = item.attributedContentText?.string.trimmingCharacters(in: .whitespacesAndNewlines)
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier), content.images.count < maxImages {
                    if let image = await copyImage(from: provider, into: scratch) { content.images.append(image) }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL, !url.isFileURL {
                        content.links.append((url, itemTitle?.isEmpty == false ? itemTitle : nil))
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
                       !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        // Some apps share a link as text.
                        if let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
                           let scheme = url.scheme, ["http", "https"].contains(scheme.lowercased()) {
                            content.links.append((url, nil))
                        } else {
                            content.texts.append(text)
                        }
                    }
                }
            }
        }
        return content
    }

    @MainActor
    private static func copyImage(from provider: NSItemProvider, into folder: URL) async -> SharedImage? {
        let type = provider.registeredContentTypes.first { $0.conforms(to: .image) } ?? .image
        let suggested = provider.suggestedName
        return await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(for: type, openInPlace: false) { url, _, _ in
                guard let url else { continuation.resume(returning: nil); return }
                var name = suggested ?? url.deletingPathExtension().lastPathComponent
                if (name as NSString).pathExtension.isEmpty { name += "." + (type.preferredFilenameExtension ?? url.pathExtension) }
                let target = folder.appending(path: "\(UUID().uuidString.prefix(8))-\(name)", directoryHint: .notDirectory)
                do {
                    try FileManager.default.copyItem(at: url, to: target)
                    continuation.resume(returning: SharedImage(url: target, name: name))
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Queues the job in the App Group inbox for the app to import.
    func queue(notebookID: String?, destination: ShareJob.Destination, title: String, comment: String) throws {
        let id = UUID()
        let folder = try ShareJob.makeFolder(id: id)
        var items: [ShareJob.Item] = links.map { .url($0.url, title: $0.title) } + texts.map { .text($0) }
        var usedNames: Set<String> = []
        for image in images {
            var name = image.name
            var n = 2
            while usedNames.contains(name) {
                name = "\((image.name as NSString).deletingPathExtension) \(n).\((image.name as NSString).pathExtension)"
                n += 1
            }
            usedNames.insert(name)
            try FileManager.default.moveItem(at: image.url, to: folder.file(name))
            items.append(.image(fileName: name))
        }
        let job = ShareJob(id: id, notebookID: notebookID, destination: destination,
                           title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : title,
                           comment: comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : comment,
                           items: items)
        try job.commit(to: folder)
        AppGroup.postShareJobQueued()
    }

    func discard() {
        try? FileManager.default.removeItem(at: scratch)
    }
}
