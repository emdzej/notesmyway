//
//  NmyApp.swift
//  nmy
//
//  Entry point; the app itself lives in the NmyUI package.
//

import NmyUI
import SwiftUI

@main
struct NmyApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(NmyAppDelegate.self) private var delegate
    private var library: Library { delegate.library }
    #else
    @State private var library = Library()
    #endif

    var body: some Scene {
        NmyScenes(library: library)
    }
}
