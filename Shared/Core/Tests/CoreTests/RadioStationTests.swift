//
//  RadioStationTests.swift
//  Core
//
//  Guards the one station identifier shared across the SiriKit media item
//  (`MediaIntentBuilder` in PlaybackCore) and the App Intents audio-schema
//  entity (`LiveRadioStationEntity` in WXYCIntents). Before #828 these were
//  three separate literals ("Play WXYC", "WXYC", "org.wxyc.live"); this test
//  pins the one `Core` now owns so a future edit to any consumer can't drift
//  it back apart.
//
//  Created by Jake Bromberg on 08/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import Core

@Suite
struct RadioStationTests {
    @Test
    func wxycIdentifierIsTheSharedMediaDomainIdentity() {
        #expect(RadioStation.WXYC.identifier == "org.wxyc.live")
    }
}
