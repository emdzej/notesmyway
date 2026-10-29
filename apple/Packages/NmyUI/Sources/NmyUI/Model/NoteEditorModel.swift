//
//  NoteEditorModel.swift
//  NmyUI
//
//  One open note: its text, autosave (500 ms after the last keystroke), and
//  what happens when the file changes underneath (spec §5). A change on
//  disk is adopted silently while there are no unsaved edits; with unsaved
//  edits it becomes a conflict the user resolves. Used for notebook notes
//  and standalone files alike.
//

import Foundation
import NmyCore
import Observation

@MainActor
@Observable
public final class NoteEditorModel {

    public enum ConflictChoice: Sendable {
        /// Overwrite the file with the text in the editor.
        case keepMine
        /// Discard the editor's changes and show the file.
        case useDisk
        /// Save the editor's text; keep the file's version as a copy next to it.
        case keepBoth
    }

    public private(set) var url: URL
    /// The editor's text. Setting it schedules a save.
    public var text: String = "" {
        didSet { if text != oldValue, !isApplyingDisk { scheduleSave() } }
    }
    /// The file as last read or written.
    public private(set) var snapshot: NoteFile.Snapshot?
    /// The file's diverging version while the editor has unsaved changes.
    public private(set) var conflict: NoteFile.Snapshot?
    public private(set) var errorMessage: String?
    public private(set) var isLoaded = false

    @ObservationIgnored public var saveDelay: Duration = .milliseconds(500)
    /// Called after every successful save (the session reindexes the note).
    @ObservationIgnored public var onSaved: ((URL) -> Void)?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var isApplyingDisk = false

    public init(url: URL) {
        self.url = url
    }

    public var fileName: String { url.deletingPathExtension().lastPathComponent }

    /// True while the editor holds text that isn't on disk.
    public var isDirty: Bool { snapshot.map { $0.text != text } ?? !text.isEmpty }

    public func load() {
        do {
            let snapshot = try NoteFile(url: url).read()
            self.snapshot = snapshot
            setTextFromDisk(snapshot.text)
            errorMessage = nil
        } catch NoteFile.Error.notUTF8 {
            errorMessage = "“\(url.lastPathComponent)” isn’t UTF-8 text, so nmy won’t edit it."
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoaded = true
    }

    /// Saves now if there are unsaved changes (note switch, window close, quit).
    public func flush() {
        saveTask?.cancel()
        saveTask = nil
        if isLoaded, isDirty, conflict == nil, errorMessage == nil { save() }
    }

    /// The file changed on disk (watcher). Adopt it when that loses nothing.
    public func diskDidChange() {
        guard isLoaded, let disk = try? NoteFile(url: url).read() else { return }
        if disk.text == snapshot?.text {
            snapshot = disk          // our own save, or a touch
        } else if disk.text == text {
            snapshot = disk          // someone wrote what we have
        } else if !isDirty {
            snapshot = disk
            setTextFromDisk(disk.text)
        } else {
            saveTask?.cancel()
            conflict = disk
        }
    }

    public func resolveConflict(_ choice: ConflictChoice) {
        guard let disk = conflict else { return }
        conflict = nil
        switch choice {
        case .useDisk:
            snapshot = disk
            setTextFromDisk(disk.text)
        case .keepMine:
            snapshot = disk
            save()
        case .keepBoth:
            let copy = Self.conflictCopyURL(for: url)
            _ = try? NoteFile(url: copy).write(disk.text, replacing: nil)
            onSaved?(copy)
            snapshot = disk
            save()
        }
    }

    /// The file was moved or renamed (by nmy or outside it).
    public func fileMoved(to newURL: URL) {
        url = newURL
        if let disk = try? NoteFile(url: newURL).read() { snapshot = disk }
    }

    /// Replaces the text with an edit computed elsewhere (link fixes), saving it.
    /// False if the editor's text isn't `expected` any more.
    @discardableResult
    public func applyEdit(from expected: String, to newText: String) -> Bool {
        guard text == expected else { return false }
        text = newText
        flush()
        return true
    }

    // MARK: Saving

    private func scheduleSave() {
        guard isLoaded, conflict == nil else { return }
        saveTask?.cancel()
        let delay = saveDelay
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    private func save() {
        do {
            snapshot = try NoteFile(url: url).write(text, replacing: snapshot)
            errorMessage = nil
            onSaved?(url)
        } catch NoteFile.Error.changedOnDisk(let current) {
            if let current, current.text == text {
                snapshot = current
            } else if let current {
                conflict = current
            } else {
                // The file is gone (deleted or moved away): write it back rather than lose the text.
                snapshot = try? NoteFile(url: url).write(text, replacing: nil)
                onSaved?(url)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setTextFromDisk(_ newText: String) {
        isApplyingDisk = true
        text = newText
        isApplyingDisk = false
    }

    /// `Note (conflict 2026-10-29 1405).md` next to the note.
    static func conflictCopyURL(for url: URL, date: Date = Date()) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? "md" : url.pathExtension
        var candidate = url.deletingLastPathComponent().appending(path: "\(stem) (conflict \(formatter.string(from: date))).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = url.deletingLastPathComponent().appending(path: "\(stem) (conflict \(formatter.string(from: date)) \(n)).\(ext)")
            n += 1
        }
        return candidate
    }
}
