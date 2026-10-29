//
//  AppGroup.swift
//  NmwShared
//
//  The container the app shares with its widgets and share extension.
//

import Foundation

public enum AppGroup {
    /// macOS uses the team-prefixed form, which needs no provisioning profile.
    #if os(macOS)
    public static let identifier = "A2WT9CD8P3.group.pl.emdzej.notesmyway"
    #else
    public static let identifier = "group.pl.emdzej.notesmyway"
    #endif

    /// Posted (Darwin notification) by the share extension after it queued a job.
    public static let shareJobQueuedNotification = "pl.emdzej.notesmyway.shareJobQueued"

    /// The shared container; nil when the group isn't available (e.g. an
    /// unsigned build), in which case the app-local fallback is used, so the
    /// app still works but extensions can't see its data.
    public static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var base: URL {
        container ?? FileManager.default.temporaryDirectory.appending(path: "nmw-group", directoryHint: .isDirectory)
    }

    /// `widgets.json`: what the widgets and the share extension show.
    public static var snapshotURL: URL { base.appending(path: "widgets.json", directoryHint: .notDirectory) }

    /// `Inbox/<job id>/`: shared content waiting for the app to import it.
    public static var inboxFolder: URL { base.appending(path: "Inbox", directoryHint: .isDirectory) }

    /// Tells a running app that a share job is waiting.
    public static func postShareJobQueued() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(shareJobQueuedNotification as CFString), nil, nil, true)
    }
}
