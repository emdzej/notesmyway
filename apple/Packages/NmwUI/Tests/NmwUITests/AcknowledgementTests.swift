//
//  AcknowledgementTests.swift
//  NmwUITests
//
//  Every licence the About page lists ships with the app and loads.
//

import Foundation
import Testing
@testable import NmwUI

@Suite("Acknowledgements")
struct AcknowledgementTests {
    @Test func everyLicenceFileLoads() {
        for item in Acknowledgement.all + [Acknowledgement.app] {
            #expect(!item.text.isEmpty, "\(item.name)")
        }
        #expect(Acknowledgement.all.first { $0.id == "markdownkit" }?.text.contains("Apache License") == true)
        #expect(Acknowledgement.all.first { $0.id == "markdownkit" }?.text.contains("swift-markdown-engine") == true)
        #expect(Acknowledgement.app.text.contains("GNU GENERAL PUBLIC LICENSE"))
    }
}
