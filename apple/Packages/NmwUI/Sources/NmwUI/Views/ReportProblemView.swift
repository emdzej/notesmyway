//
//  ReportProblemView.swift
//  NmwUI
//
//  Help › Report a Problem… (and the notebook menu, the palette): ALIAS's
//  report sheet, in the app's language. A screenshot of the window is taken
//  when the sheet opens but only sent if the user adds it: it may show a
//  note. Added, it can be blacked out first.
//

import AliasSupport
import AliasSupportUI
import SwiftUI

struct ReportProblemView: View {
    let client: AliasClient
    /// The window as it was when Report a Problem was chosen.
    let window: CGImage?
    @Environment(\.dismiss) private var dismiss
    @State private var addsScreenshot = false

    var body: some View {
        NavigationStack {
            AliasReportView(client: client, screenshot: addsScreenshot ? window : nil, labels: .nmw)
                .formStyle(.grouped)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                    if window != nil, !addsScreenshot {
                        ToolbarItem(placement: .automatic) {
                            Button("Add Screenshot", systemImage: "camera.viewfinder") { addsScreenshot = true }
                                .help("Adds a picture of the window, which you can black out before sending")
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        NavigationLink(AliasLabels.nmw.yourReports) {
                            AliasTicketsView(client: client, labels: .nmw)
                        }
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 520, minHeight: 440, idealHeight: 560)
        #endif
    }
}

extension AliasLabels {
    /// The sheet's words, from the app's catalog (English and Polish).
    static var nmw: AliasLabels {
        var l = AliasLabels()
        l.redactTitle = String(localized: "Black out what you don’t want to send")
        l.box = String(localized: "Box")
        l.brush = String(localized: "Brush")
        l.undo = String(localized: "Undo")
        l.clear = String(localized: "Clear")
        l.cancel = String(localized: "Cancel")
        l.done = String(localized: "Done")
        l.reportTitle = String(localized: "Report a Problem")
        l.notePrompt = String(localized: "What happened?")
        l.screenshot = String(localized: "Screenshot")
        l.includeScreenshot = String(localized: "Send the screenshot")
        l.blackOut = String(localized: "Black Out Parts…")
        l.whatsSent = String(localized: "Sent with the report")
        l.nothingElse = String(localized: "Nothing else.")
        l.contactTitle = String(localized: "A way to reach you (optional)")
        l.contactPlaceholder = String(localized: "you@example.com")
        l.agree = String(localized: "I agree")
        l.send = String(localized: "Send")
        l.sending = String(localized: "Sending…")
        l.sent = String(localized: "Sent. Support’s answer will show in Your Reports.")
        l.yourReports = String(localized: "Your Reports")
        l.noReports = String(localized: "No reports yet.")
        l.replyPrompt = String(localized: "Write a reply")
        l.talkLive = String(localized: "Talk Live")
        l.liveAsked = String(localized: "Asked: someone will join when they can.")
        l.liveNow = String(localized: "Live: support is here.")
        l.typing = String(localized: "Support is typing…")
        l.agent = String(localized: "Answered by an agent, not a person")
        l.support = String(localized: "Support")
        l.you = String(localized: "You")
        l.statusWords = [
            "open": String(localized: "Open"),
            "in_progress": String(localized: "In progress"),
            "waiting": String(localized: "Waiting on you"),
            "resolved": String(localized: "Resolved"),
            "closed": String(localized: "Closed"),
        ]
        return l
    }
}
