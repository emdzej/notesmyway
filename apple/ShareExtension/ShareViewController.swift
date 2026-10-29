//
//  ShareViewController.swift
//  NmwShare
//
//  The extension's principal class: hosts `ShareView`.
//

import SwiftUI

#if os(iOS)
import UIKit

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let host = UIHostingController(rootView: ShareView(load: { await ShareContent.load(from: items) }) { [weak self] saved in
            self?.finish(saved)
        })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func finish(_ saved: Bool) {
        if saved {
            extensionContext?.completeRequest(returningItems: nil)
        } else {
            extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        }
    }
}
#else
import AppKit

final class ShareViewController: NSViewController {
    override func loadView() {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        view = NSHostingView(rootView: ShareView(load: { await ShareContent.load(from: items) }) { [weak self] saved in
            self?.finish(saved)
        })
        view.frame = NSRect(x: 0, y: 0, width: 420, height: 380)
    }

    private func finish(_ saved: Bool) {
        if saved {
            extensionContext?.completeRequest(returningItems: nil)
        } else {
            extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        }
    }
}
#endif
