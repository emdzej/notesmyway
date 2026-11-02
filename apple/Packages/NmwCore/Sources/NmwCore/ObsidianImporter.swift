//
//  ObsidianImporter.swift
//  NmwCore
//
//  Copies an Obsidian vault into a notebook folder as standard Markdown.
//  Notes keep their folders, names and dates. Wikilinks become links with
//  relative paths (`[[Note|Alias]]` → `[Alias](Note.md)`), embeds become
//  images or links, and every linked attachment moves into the notebook's
//  attachment folder (its settings). Files no note links to are copied
//  where they were. Hidden folders (`.obsidian`, `.trash`) are left out, and
//  nothing in the vault is changed.
//
//  Links resolve the way Obsidian resolves them: relative to the note,
//  then from the vault's root, then by file name anywhere in the vault
//  (the nearest match when names repeat).
//

import Foundation
import UniformTypeIdentifiers

public struct ObsidianImporter: Sendable {
    public struct Report: Sendable, Equatable {
        public var imported = 0
        /// Attachment files copied into attachment folders.
        public var attachments = 0
        /// Files no note links to, copied where they were in the vault.
        public var otherFiles = 0
        /// Links to notes or files that aren't in the vault; left as written.
        public var unresolvedLinks = 0
        /// `![[Note]]` embeds, which became links (nmw doesn't show one note inside another).
        public var embeddedNotes = 0
        public var failures: [String] = []
        /// The folder the notes went to.
        public var destination: URL?
        /// The notes written.
        public var files: [URL] = []
    }

    /// What's in a vault, read by `scan(_:)`.
    public struct Vault: Sendable, Equatable {
        public let root: URL
        /// Vault-relative paths of the notes (`.md`).
        public let notes: [String]
        /// Vault-relative paths of every other file.
        public let files: [String]
        /// Bytes of all of them.
        public let size: Int64
        /// True when the folder has Obsidian's `.obsidian` settings folder.
        public let hasSettings: Bool
    }

    public let vault: Vault
    /// The notebook's root, for attachment placement.
    public let notebookRoot: URL
    public var layout = NotebookConfig.Attachments()

    public init(vault: Vault, notebookRoot: URL, layout: NotebookConfig.Attachments = NotebookConfig.Attachments()) {
        self.vault = vault
        self.notebookRoot = notebookRoot
        self.layout = layout
    }

    /// Lists a vault's notes and files, skipping hidden ones. Reads file sizes,
    /// so call it off the main thread.
    public static func scan(_ root: URL) -> Vault {
        let base = root.standardizedFileURL.resolvingSymlinksInPath()
        let prefix = base.path.hasSuffix("/") ? base.path : base.path + "/"
        var notes: [String] = [], files: [String] = [], size: Int64 = 0
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        if let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let url as URL in walker {
                guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
                let path = url.standardizedFileURL.resolvingSymlinksInPath().path
                guard path.hasPrefix(prefix) else { continue }
                let relative = String(path.dropFirst(prefix.count)).precomposedStringWithCanonicalMapping
                if url.pathExtension.lowercased() == "md" { notes.append(relative) } else { files.append(relative) }
                size += Int64(values.fileSize ?? 0)
            }
        }
        let hasSettings = FileManager.default.fileExists(atPath: base.appending(path: ".obsidian").path)
        return Vault(root: base, notes: notes.sorted(), files: files.sorted(), size: size, hasSettings: hasSettings)
    }

    /// Imports into `destination` (created if needed); `progress` gets (done, total).
    public func run(into destination: URL, progress: (Int, Int) -> Void = { _, _ in }) -> Report {
        var report = Report(destination: destination)
        let index = Index(vault)
        var stored: [String: URL] = [:]       // "<attachment folder>|<vault path>" → the copy
        var linked = Set<String>()

        for (n, note) in vault.notes.enumerated() {
            defer { progress(n + 1, vault.notes.count) }
            let source = vault.root.appending(path: note)
            let target = destination.appending(path: note)
            do {
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                if let text = try? String(contentsOf: source, encoding: .utf8) {
                    var converter = Converter(note: note, noteURL: target, destination: destination, index: index)
                    let converted = converter.convert(text) { file in
                        linked.insert(file)
                        let folder = AttachmentStore.folder(for: target, notebookRoot: notebookRoot, layout: layout)
                        let key = folder.path + "|" + file
                        if let copy = stored[key] { return copy }
                        guard let copy = try? AttachmentStore.store(vault.root.appending(path: file), for: target,
                                                                    notebookRoot: notebookRoot, layout: layout) else { return nil }
                        if !copy.reused { report.attachments += 1 }
                        stored[key] = copy.url
                        return copy.url
                    }
                    report.unresolvedLinks += converter.unresolved
                    report.embeddedNotes += converter.embeddedNotes
                    try converted.write(to: target, atomically: true, encoding: .utf8)
                } else {
                    // Not UTF-8: keep it as it is.
                    try FileManager.default.copyItem(at: source, to: target)
                }
                Self.copyDates(from: source, to: target)
                report.imported += 1
                report.files.append(target)
            } catch {
                report.failures.append(note)
            }
        }

        for file in vault.files where !linked.contains(file) {
            let source = vault.root.appending(path: file)
            let target = destination.appending(path: file)
            do {
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: source, to: target)
                Self.copyDates(from: source, to: target)
                report.otherFiles += 1
            } catch {
                report.failures.append(file)
            }
        }
        return report
    }

    private static func copyDates(from source: URL, to target: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: source.path) else { return }
        var dates: [FileAttributeKey: Any] = [:]
        if let created = attributes[.creationDate] { dates[.creationDate] = created }
        if let modified = attributes[.modificationDate] { dates[.modificationDate] = modified }
        try? FileManager.default.setAttributes(dates, ofItemAtPath: target.path)
    }

    // MARK: Resolving

    enum Target: Equatable {
        case note(String)
        case file(String)
    }

    /// The vault's files by path and by name, lowercased, as Obsidian matches them.
    struct Index {
        var notesByPath: [String: String] = [:]   // path without `.md`
        var notesByName: [String: [String]] = [:] // name without `.md`
        var filesByPath: [String: String] = [:]
        var filesByName: [String: [String]] = [:]

        init(_ vault: Vault) {
            for note in vault.notes {
                let stem = String(note.dropLast(3)).lowercased()
                notesByPath[stem] = note
                notesByName[Self.name(stem), default: []].append(note)
            }
            for file in vault.files {
                filesByPath[file.lowercased()] = file
                filesByName[Self.name(file.lowercased()), default: []].append(file)
            }
        }

        static func name(_ path: String) -> String { path.split(separator: "/").last.map(String.init) ?? path }

        /// `link` (unencoded, without `#fragment`) as written in `note`.
        func resolve(_ link: String, from note: String) -> Target? {
            var path = link.trimmingCharacters(in: .whitespaces).precomposedStringWithCanonicalMapping
            guard !path.isEmpty else { return nil }
            let rooted = path.hasPrefix("/")
            while path.hasPrefix("/") { path.removeFirst() }
            let folder = note.split(separator: "/").dropLast().joined(separator: "/")
            var candidates: [String] = []
            if !rooted, let relative = Self.normalized(folder.isEmpty ? path : folder + "/" + path) { candidates.append(relative) }
            if let fromRoot = Self.normalized(path) { candidates.append(fromRoot) }
            for candidate in candidates {
                if let hit = lookUp(path: candidate.lowercased()) { return hit }
            }
            // By name anywhere in the vault (`[[Folder/Note]]` also matches `…/Folder/Note`): the match nearest the note.
            let lowered = path.lowercased()
            let name = Self.name(lowered)
            let stem = name.hasSuffix(".md") ? String(name.dropLast(3)) : name
            let suffix = "/" + (lowered.hasSuffix(".md") ? String(lowered.dropLast(3)) : lowered)
            func matching(_ paths: [String], dropping ext: Int) -> [String] {
                guard lowered.contains("/") else { return paths }
                return paths.filter { ("/" + $0.lowercased().dropLast(ext)).hasSuffix(suffix) }
            }
            if !name.hasSuffix(".md"), let files = filesByName[name], let best = nearest(matching(files, dropping: 0), to: folder) { return .file(best) }
            if let notes = notesByName[stem], let best = nearest(matching(notes, dropping: 3), to: folder) { return .note(best) }
            return nil
        }

        private func lookUp(path: String) -> Target? {
            if path.hasSuffix(".md"), let note = notesByPath[String(path.dropLast(3))] { return .note(note) }
            if let file = filesByPath[path] { return .file(file) }
            if let note = notesByPath[path] { return .note(note) }
            return nil
        }

        /// Same folder first, then the fewest folders apart, then by name.
        private func nearest(_ paths: [String], to folder: String) -> String? {
            let here = folder.lowercased().split(separator: "/")
            func distance(_ path: String) -> Int {
                let there = path.lowercased().split(separator: "/").dropLast()
                var common = 0
                while common < here.count, common < there.count, here[common] == there[common] { common += 1 }
                return (here.count - common) + (there.count - common)
            }
            return paths.min { (distance($0), $0) < (distance($1), $1) }
        }

        /// `a/./b/../c` → `a/c`; nil when it climbs out of the vault.
        static func normalized(_ path: String) -> String? {
            var parts: [Substring] = []
            for part in path.split(separator: "/") {
                if part == "." { continue }
                if part == ".." {
                    guard !parts.isEmpty else { return nil }
                    parts.removeLast()
                } else {
                    parts.append(part)
                }
            }
            return parts.isEmpty ? nil : parts.joined(separator: "/")
        }
    }

    // MARK: Converting a note

    struct Converter {
        let note: String
        let noteURL: URL
        /// Where the vault's notes go.
        let destination: URL
        let index: Index
        var unresolved = 0
        var embeddedNotes = 0

        /// `text` with wikilinks, embeds and links to moved files rewritten.
        /// `store` copies an attachment (vault path) and returns the copy.
        mutating func convert(_ text: String, store: (String) -> URL?) -> String {
            var replacements: [(Range<String.Index>, String)] = []

            var fence = FenceTracker()
            for line in Frontmatter.body(of: text).split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
                if fence.isCode(line) { continue }
                let code = LinkScanner.codeSpans(in: line)
                for wikilink in Self.wikilinks(in: line) where !code.contains(where: { $0.overlaps(wikilink.range) }) {
                    if let markdown = markdown(for: wikilink, store: store) {
                        replacements.append((wikilink.range, markdown))
                    } else {
                        unresolved += 1
                    }
                }
            }

            // Standard links: point links at moved attachments and vault-rooted paths at relative ones.
            for occurrence in LinkScanner.occurrences(in: text)
            where !replacements.contains(where: { $0.0.overlaps(occurrence.range) }) {
                let destination = occurrence.destination
                guard !destination.hasPrefix("#"), !Self.hasScheme(destination) else { continue }
                let parts = destination.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                let path = String(parts[0]).removingPercentEncoding ?? String(parts[0])
                guard let target = index.resolve(path, from: note) else { unresolved += 1; continue }
                guard var link = self.link(to: target, store: store) else { unresolved += 1; continue }
                if parts.count > 1 { link += "#" + parts[1] }
                if link != String(text[occurrence.range]) { replacements.append((occurrence.range, link)) }
            }

            var result = text
            for (range, replacement) in replacements.sorted(by: { $0.0.lowerBound > $1.0.lowerBound }) {
                result.replaceSubrange(range, with: replacement)
            }
            return result
        }

        /// The encoded relative destination for a resolved target.
        private func link(to target: Target, store: (String) -> URL?) -> String? {
            switch target {
            case .note(let path):
                // Notes keep their places in the vault.
                return LinkPath.encode(LinkPath.relative(from: noteURL, to: destination.appending(path: path)))
            case .file(let path):
                return store(path).map { LinkPath.encode(LinkPath.relative(from: noteURL, to: $0)) }
            }
        }

        private mutating func markdown(for wikilink: Wikilink, store: (String) -> URL?) -> String? {
            let heading = wikilink.fragment.flatMap { $0.hasPrefix("^") ? nil : $0 }   // `^block` ids have no counterpart
            if wikilink.target.isEmpty {
                // `[[#Heading]]`: a heading in this note.
                guard let heading else { return nil }
                return "[\(Self.escape(wikilink.alias ?? heading))](#\(Self.slug(heading)))"
            }
            guard let target = index.resolve(wikilink.target, from: note), let destination = link(to: target, store: store) else { return nil }
            let name = Index.name(wikilink.target)
            switch target {
            case .note:
                if wikilink.isEmbed { embeddedNotes += 1 }
                let title = name.lowercased().hasSuffix(".md") ? String(name.dropLast(3)) : name
                let text = wikilink.alias ?? (heading.map { "\(title) › \($0)" } ?? title)
                return "[\(Self.escape(text))](\(destination)\(heading.map { "#" + Self.slug($0) } ?? ""))"
            case .file(let path):
                let isImage = UTType(filenameExtension: (path as NSString).pathExtension)?.conforms(to: .image) ?? false
                guard wikilink.isEmbed, isImage else {
                    return "[\(Self.escape(wikilink.alias ?? name))](\(destination))"
                }
                // `|300` or `|300x200` is a size; anything else is alt text.
                if let alias = wikilink.alias, let size = Self.size(alias) {
                    return "![](\(destination)){width=\(size.width)" + (size.height.map { " height=\($0)" } ?? "") + "}"
                }
                return "![\(Self.escape(wikilink.alias ?? ""))](\(destination))"
            }
        }

        struct Wikilink: Equatable {
            let range: Range<String.Index>
            let isEmbed: Bool
            let target: String
            let fragment: String?
            let alias: String?
        }

        /// `[[target#fragment|alias]]` and `![[…]]` on a line.
        static func wikilinks(in line: Substring) -> [Wikilink] {
            var result: [Wikilink] = []
            var i = line.startIndex
            while let open = line[i...].range(of: "[["), let close = line[open.upperBound...].range(of: "]]") {
                let inner = line[open.upperBound..<close.lowerBound]
                i = close.upperBound
                let escaped = open.lowerBound > line.startIndex && line[line.index(before: open.lowerBound)] == "\\"
                guard !escaped, !inner.isEmpty, !inner.contains("[") else {
                    i = line.index(after: open.lowerBound)
                    continue
                }
                let isEmbed = open.lowerBound > line.startIndex && line[line.index(before: open.lowerBound)] == "!"
                let start = isEmbed ? line.index(before: open.lowerBound) : open.lowerBound
                // In tables the pipe is escaped: `[[Note\|Alias]]`.
                var link = String(inner), alias: String?
                if let bar = link.firstIndex(of: "|") {
                    alias = String(link[link.index(after: bar)...]).trimmingCharacters(in: .whitespaces)
                    link = String(link[..<bar])
                    if link.hasSuffix("\\") { link.removeLast() }
                }
                var fragment: String?
                if let hash = link.firstIndex(of: "#") {
                    fragment = String(link[link.index(after: hash)...]).trimmingCharacters(in: .whitespaces)
                    link = String(link[..<hash])
                }
                result.append(Wikilink(range: start..<close.upperBound, isEmbed: isEmbed,
                                       target: link.trimmingCharacters(in: .whitespaces), fragment: fragment,
                                       alias: alias.flatMap { $0.isEmpty ? nil : $0 }))
            }
            return result
        }

        /// `300` → 300 wide; `300x200` → 300 × 200.
        static func size(_ alias: String) -> (width: Int, height: Int?)? {
            let parts = alias.split(separator: "x", maxSplits: 1).map { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard let width = parts.first ?? nil, width > 0 else { return nil }
            if parts.count == 2 {
                guard let height = parts[1] else { return nil }
                return (width, height)
            }
            return (width, nil)
        }

        /// GitHub's heading anchors: lowercased, punctuation dropped, spaces to hyphens.
        static func slug(_ heading: String) -> String {
            let kept = heading.lowercased().unicodeScalars.filter {
                CharacterSet.alphanumerics.contains($0) || $0 == " " || $0 == "-" || $0 == "_"
            }
            let slug = String(String.UnicodeScalarView(kept)).replacingOccurrences(of: " ", with: "-")
            return slug.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? slug
        }

        static func escape(_ text: String) -> String {
            var out = ""
            for ch in text {
                if "\\[]".contains(ch) { out.append("\\") }
                out.append(ch)
            }
            return out
        }

        static func hasScheme(_ destination: String) -> Bool {
            destination.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#, options: .regularExpression) != nil
        }
    }
}
