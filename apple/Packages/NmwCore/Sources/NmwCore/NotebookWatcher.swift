//
//  NotebookWatcher.swift
//  NmwCore
//
//  Reports files that change in a notebook folder, from any source.
//  macOS uses FSEvents, which also sees uncoordinated writers (vim, git,
//  Syncthing); iOS uses a file presenter on the folder (Files app, other
//  apps writing through coordination). Events are coalesced, then handed
//  to the indexer; `changes(of:)` streams the resulting index changes.
//

import Foundation
#if os(macOS)
import CoreServices
#endif

public final class NotebookWatcher: @unchecked Sendable {
    public let notebook: Notebook
    private let latency: TimeInterval
    private let handler: @Sendable ([NotebookPath], _ rescan: Bool) -> Void
    private let queue = DispatchQueue(label: "nmw.notebook-watcher")

    // State below is only touched on `queue`.
    private var pending: Set<NotebookPath> = []
    private var pendingRescan = false
    private var flushScheduled = false
    #if os(macOS)
    private var stream: FSEventStreamRef?
    #else
    private var presenter: FolderPresenter?
    #endif

    /// `handler` gets coalesced notebook paths (files or folders) that may
    /// have changed, or `rescan` when the system lost track and a full
    /// `sync()` is needed. It runs on a private queue.
    public init(notebook: Notebook, latency: TimeInterval = 0.3,
                handler: @escaping @Sendable ([NotebookPath], _ rescan: Bool) -> Void) {
        self.notebook = notebook
        self.latency = latency
        self.handler = handler
    }

    deinit { stopOnQueue() }

    public func start() {
        queue.sync { startOnQueue() }
    }

    public func stop() {
        queue.sync { stopOnQueue() }
    }

    /// Index changes as files change: each batch of events runs through
    /// `indexer.update` (or `sync` on a rescan); empty results are skipped.
    /// Watching stops when the stream's consumer goes away.
    public static func changes(of indexer: NotebookIndexer, latency: TimeInterval = 0.3) -> AsyncStream<IndexChanges> {
        AsyncStream { continuation in
            let watcher = NotebookWatcher(notebook: indexer.notebook, latency: latency) { paths, rescan in
                Task {
                    let changes = try? await (rescan ? indexer.sync() : indexer.update(paths))
                    if let changes, !changes.isEmpty || !changes.failed.isEmpty { continuation.yield(changes) }
                }
            }
            continuation.onTermination = { _ in watcher.stop() }
            watcher.start()
        }
    }

    // MARK: Coalescing

    private func receive(_ urls: [URL], rescan: Bool) {
        queue.async { [self] in
            if rescan { pendingRescan = true }
            for url in urls {
                if let path = notebook.path(for: url), !path.components.contains(where: { $0.hasPrefix(".") }) {
                    pending.insert(path)
                } else if NotebookPath.canonicalComponents(url) == NotebookPath.canonicalComponents(notebook.root) {
                    pendingRescan = true   // the folder itself changed (moved, replaced)
                }
            }
            guard !flushScheduled, pendingRescan || !pending.isEmpty else { return }
            flushScheduled = true
            queue.asyncAfter(deadline: .now() + latency) { [self] in
                let paths = Array(pending)
                let rescan = pendingRescan
                pending = []
                pendingRescan = false
                flushScheduled = false
                handler(paths, rescan)
            }
        }
    }

    // MARK: Platform sources

    #if os(macOS)
    private func startOnQueue() {
        guard stream == nil else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info else { return }
            let watcher = Unmanaged<NotebookWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            let rescanFlags = UInt32(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped
                                     | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagRootChanged)
            let rescan = UnsafeBufferPointer(start: flags, count: count).contains { $0 & rescanFlags != 0 }
            watcher.receive(list.map { URL(fileURLWithPath: $0) }, rescan: rescan)
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
                                             | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot)
        guard let stream = FSEventStreamCreate(nil, callback, &context, [notebook.root.path] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags) else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    private func stopOnQueue() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
    #else
    private func startOnQueue() {
        guard presenter == nil else { return }
        let presenter = FolderPresenter(url: notebook.root) { [weak self] urls in self?.receive(urls, rescan: false) }
        NSFileCoordinator.addFilePresenter(presenter)
        self.presenter = presenter
    }

    private func stopOnQueue() {
        guard let presenter else { return }
        NSFileCoordinator.removeFilePresenter(presenter)
        self.presenter = nil
    }
    #endif
}

#if !os(macOS)
/// Presents the notebook folder to hear about coordinated changes inside it.
private final class FolderPresenter: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private let changed: ([URL]) -> Void

    init(url: URL, changed: @escaping ([URL]) -> Void) {
        presentedItemURL = url
        self.changed = changed
    }

    func presentedSubitemDidAppear(at url: URL) { changed([url]) }
    func presentedSubitemDidChange(at url: URL) { changed([url]) }
    func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) { changed([oldURL, newURL]) }
    func accommodatePresentedSubitemDeletion(at url: URL, completionHandler: @escaping @Sendable (Error?) -> Void) {
        changed([url])
        completionHandler(nil)
    }
}
#endif
