//
//  NoteFile.swift
//  NmyCore
//
//  Reading and saving one markdown file, wherever it lives: in a notebook or
//  standalone (opened from Finder / Files). Reads and writes are
//  file-coordinated (iCloud, other apps) and writes are atomic, so a crash
//  never leaves half a note. Saving refuses to overwrite a file that
//  changed on disk since it was read.
//

import Foundation

public struct NoteFile: Sendable, Hashable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// A version of the file's contents as read.
    public struct Snapshot: Sendable, Equatable {
        /// The contents, without a UTF-8 byte-order mark.
        public let text: String
        /// Whether the file starts with a byte-order mark; saving keeps it.
        public let hasByteOrderMark: Bool
        /// Modification date and size when read; a save checks them.
        public let modified: Date?
        public let size: Int
    }

    public enum Error: Swift.Error, Equatable {
        /// The bytes aren't UTF-8; nmy won't rewrite them.
        case notUTF8
        /// The file changed on disk after `expected` was read.
        case changedOnDisk(current: Snapshot?)
    }

    public var fileName: String { url.deletingPathExtension().lastPathComponent }

    public func read() throws -> Snapshot {
        var result: Result<Snapshot, Swift.Error> = .failure(CocoaError(.fileReadUnknown))
        try Coordination.read(url) { url in
            result = Result { try Self.uncoordinatedSnapshot(url) }
        }
        return try result.get()
    }

    /// Writes `text` and returns the new snapshot. With `replacing`, the
    /// write only happens if the file still matches it (same date and size);
    /// pass nil to create a file or to overwrite unconditionally.
    @discardableResult
    public func write(_ text: String, replacing expected: Snapshot?) throws -> Snapshot {
        let bom = expected?.hasByteOrderMark ?? false
        let data = (bom ? Self.byteOrderMark : Data()) + Data(text.utf8)
        var result: Result<Snapshot, Swift.Error> = .failure(CocoaError(.fileWriteUnknown))
        try Coordination.write(url) { url in
            result = Result {
                if let expected {
                    let now = Self.attributes(of: url)
                    if now.modified != expected.modified || now.size != expected.size {
                        throw Error.changedOnDisk(current: try? Self.uncoordinatedSnapshot(url))
                    }
                }
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
                let attributes = Self.attributes(of: url)
                return Snapshot(text: text, hasByteOrderMark: bom, modified: attributes.modified, size: attributes.size ?? data.count)
            }
        }
        return try result.get()
    }

    private static let byteOrderMark = Data([0xEF, 0xBB, 0xBF])

    static func attributes(of url: URL) -> (modified: Date?, size: Int?) {
        var url = url
        url.removeAllCachedResourceValues()   // URLs cache resource values
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return (values?.contentModificationDate, values?.fileSize)
    }

    private static func uncoordinatedSnapshot(_ url: URL) throws -> Snapshot {
        let data = try Data(contentsOf: url)
        let bom = data.starts(with: byteOrderMark)
        // Decode without the mark explicitly; Foundation strips it silently otherwise.
        guard let text = String(data: bom ? data.dropFirst(3) : data, encoding: .utf8) else { throw Error.notUTF8 }
        let attributes = attributes(of: url)
        return Snapshot(text: text, hasByteOrderMark: bom, modified: attributes.modified, size: attributes.size ?? data.count)
    }
}

/// `NSFileCoordinator` with errors thrown instead of passed through pointers.
enum Coordination {
    static func read(_ url: URL, _ body: (URL) -> Void) throws {
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error, byAccessor: body)
        if let error { throw error }
    }

    static func write(_ url: URL, _ body: (URL) -> Void) throws {
        var error: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &error, byAccessor: body)
        if let error { throw error }
    }
}
