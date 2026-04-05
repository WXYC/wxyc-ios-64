//
//  LinkButtonLabelTests.swift
//  WXYC
//
//  Tests for LinkButtonLabel, the shared label component used by StreamingButton
//  and ExternalLinkButton.
//
//  Created by Jake Bromberg on 03/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import SwiftUI
@testable import WXYC

@Suite("LinkButtonLabel.Icon Tests")
struct LinkButtonLabelIconTests {

    @Test("Custom icon stores name and bundle")
    func customIconProperties() {
        let icon = LinkButtonLabel.Icon.custom(name: "spotify", bundle: .main)

        switch icon {
        case .custom(let name, let bundle):
            #expect(name == "spotify")
            #expect(bundle == .main)
        case .system:
            Issue.record("Expected custom icon")
        }
    }

    @Test("System icon stores name")
    func systemIconProperties() {
        let icon = LinkButtonLabel.Icon.system(name: "waveform")

        switch icon {
        case .system(let name):
            #expect(name == "waveform")
        case .custom:
            Issue.record("Expected system icon")
        }
    }

    @Test("Custom and system icons are distinct cases")
    func iconCasesAreDistinct() {
        let custom = LinkButtonLabel.Icon.custom(name: "test", bundle: .main)
        let system = LinkButtonLabel.Icon.system(name: "test")

        if case .custom = custom {} else {
            Issue.record("Expected custom case")
        }

        if case .system = system {} else {
            Issue.record("Expected system case")
        }
    }
}
