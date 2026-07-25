//
//  WidgetToggleWXYCTests.swift
//  WXYCIntents
//
//  Structural coverage for the widget-only toggle intent (#668). `perform()`
//  itself isn't exercised here — like `ToggleWXYC`/`PlayWXYC`/`PauseWXYC`, it
//  drives the live `AudioPlayerController.shared` singleton and isn't
//  DI-seamed for a unit test (see `IntentPlaybackTests` for the one piece of
//  intent logic that is: the shared await-playback-start loop). What matters
//  here is that this intent stays a widget-only implementation detail — never
//  surfaced to Siri/Shortcuts, which would defeat the point of splitting it
//  from `ToggleWXYC` (#668).
//
//  Created by Jake Bromberg on 07/25/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import WXYCIntents

@Suite("WidgetToggleWXYC")
struct WidgetToggleWXYCTests {
    @Test("Is not discoverable to Siri/Shortcuts — widget-button use only")
    func isNotDiscoverable() {
        #expect(WidgetToggleWXYC.isDiscoverable == false)
    }

    @Test("Runs in the background without opening the app")
    func runsInBackgroundWithoutOpeningApp() {
        #expect(WidgetToggleWXYC.openAppWhenRun == false)
    }
}
