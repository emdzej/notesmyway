//
//  AboutView.swift
//  NmwUI
//
//  Settings › About: the version, and the open-source software in the app
//  with each licence's full text (Apache 2.0 asks for it to ship with the
//  app; the MIT and BSD licences ask for their notices).
//

import SwiftUI

struct Acknowledgement: Identifiable {
    let id: String
    let name: String
    let detail: String
    let license: String
    let url: URL
    /// Text files in Resources/Acknowledgements, shown one after another.
    let files: [String]

    /// Notes my Way's own licence.
    static let app = Acknowledgement(id: "notesmyway", name: "Notes my Way",
                                     detail: "Free software: you may share and change it under the GPL.",
                                     license: "GPLv3 or later", url: URL(string: "https://notesmyway.emdzej.pl")!,
                                     files: ["GPL-3.0"])

    static let all: [Acknowledgement] = [
        Acknowledgement(id: "markdownkit", name: "MarkdownKit",
                        detail: "The editor. Derived from swift-markdown-engine by Luca Chen and contributors.",
                        license: "Apache 2.0", url: URL(string: "https://github.com/emdzej/markdownkit")!,
                        files: ["MarkdownKit-NOTICE", "Apache-2.0"]),
        Acknowledgement(id: "swift-markdown-engine", name: "swift-markdown-engine",
                        detail: "The TextKit 2 editor MarkdownKit grew from. Copyright 2026 Luca Chen and contributors.",
                        license: "Apache 2.0", url: URL(string: "https://github.com/nodes-app/swift-markdown-engine")!,
                        files: ["Apache-2.0"]),
        Acknowledgement(id: "grdb", name: "GRDB", detail: "The SQLite index for search, tags and backlinks.",
                        license: "MIT", url: URL(string: "https://github.com/groue/GRDB.swift")!, files: ["GRDB"]),
        Acknowledgement(id: "highlighter", name: "HighlighterSwift and highlight.js", detail: "Syntax colours in code blocks.",
                        license: "MIT, BSD 3-Clause", url: URL(string: "https://github.com/smittytone/HighlighterSwift")!,
                        files: ["HighlighterSwift"]),
        Acknowledgement(id: "swiftmath", name: "SwiftMath", detail: "LaTeX formulas, with its math fonts.",
                        license: "MIT; fonts: SIL OFL, GUST", url: URL(string: "https://github.com/mgriebling/SwiftMath")!,
                        files: ["SwiftMath", "STIX-Fonts-OFL", "GUST-Font-License"]),
    ]

    var text: String {
        files.compactMap { name in
            Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Acknowledgements")
                .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        }
        .joined(separator: "\n\n————————\n\n")
    }
}

struct AboutView: View {
    @State private var showing: Acknowledgement?

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    #if os(iOS)
                    AppIconImage().frame(width: 56, height: 56)
                    #else
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                    #endif
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notes my Way").font(.headline)
                        Text("Version \(version)").foregroundStyle(.secondary)
                        Link("notesmyway.emdzej.pl", destination: URL(string: "https://notesmyway.emdzej.pl")!)
                            .font(.callout)
                    }
                }
                .padding(.vertical, 4)
                row(Acknowledgement.app)
            }
            Section {
                ForEach(Acknowledgement.all) { row($0) }
            } header: {
                Text("Acknowledgements")
            } footer: {
                Text("Notes my Way is built with this open-source software. Thank you to its authors.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(item: $showing) { LicenseView(item: $0) }
    }

    private func row(_ item: Acknowledgement) -> some View {
        Button { showing = item } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).foregroundStyle(.primary)
                    Text(item.detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(item.license).font(.caption).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct LicenseView: View {
    let item: Acknowledgement
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Link(item.url.absoluteString, destination: item.url).font(.callout)
                    Text(item.text)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .navigationTitle(item.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        #if os(macOS)
        .frame(width: 560, height: 520)
        #endif
    }
}
