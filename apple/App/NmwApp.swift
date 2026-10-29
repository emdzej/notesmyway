//
//  NmwApp.swift
//  nmw
//
//  Entry point; the app itself lives in the NmwUI package.
//

import NmwUI
import SwiftUI

@main
struct NmwApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(NmwAppDelegate.self) private var delegate
    private var library: Library { delegate.library }
    #else
    @State private var library = Library.shared
    #endif

    var body: some Scene {
        NmwScenes(library: library)
    }
}
