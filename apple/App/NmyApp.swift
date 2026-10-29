//
//  NmyApp.swift
//  nmy
//
//  App skeleton. The notebook UI (three columns) and the standalone-file
//  window come in M3; this target exists so both packages build into one
//  multiplatform app and `.md` is registered as a document type.
//

import NmyCore
import SwiftUI

@main
struct NmyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentUnavailableView("nmy", systemImage: "note.text", description: Text("Notebooks arrive in M3."))
        }
    }
}
