//
//  Support.swift
//  NmyCoreTests
//

import Foundation
@testable import NmyCore

/// A throwaway folder; removed by `delete()` (call it in `defer`).
struct TempFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "nmycore-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    @discardableResult
    func write(_ path: String, _ text: String) throws -> URL {
        try write(path, data: Data(text.utf8))
    }

    @discardableResult
    func write(_ path: String, data: Data) throws -> URL {
        let file = url.appending(path: path, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file)
        return file
    }

    func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}

func path(_ s: String) -> NotebookPath { NotebookPath(s)! }
