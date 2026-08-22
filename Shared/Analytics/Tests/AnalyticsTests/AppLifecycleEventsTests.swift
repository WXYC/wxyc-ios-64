//
//  AppLifecycleEventsTests.swift
//  Analytics
//
//  Property-shape coverage for the app-lifecycle events, and in particular for
//  `foreground_session` — the only event that carries how long the app was
//  actually on screen. Its two neighbours (`app_entered_background`,
//  `Application Backgrounded`) record the edge and nothing about the visit
//  that led to it.
//
//  Created by Jake Bromberg on 08/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import Analytics

@Suite("App lifecycle events")
struct AppLifecycleEventsTests {

    @Test("ForegroundSession carries the on-screen duration and whether audio outlived the visit")
    func foregroundSessionProperties() throws {
        let event = ForegroundSession(durationSeconds: 12.5, isPlaying: true)
        let props = try #require(event.properties)
        // 12.5, not 12: the median visit is on the order of ten seconds, so
        // truncating to whole seconds — or typing this as an Int — would
        // quantize away most of the distribution the event exists to measure.
        #expect(props["duration_seconds"] as? Double == 12.5)
        #expect(props["is_playing"] as? Bool == true)
        #expect(props.count == 2)
        // The name itself is pinned once, in `EventNameStabilityTests`.
    }

    @Test("AppEnteredBackground still carries only the playback flag")
    func appEnteredBackgroundProperties() throws {
        // Pinned because `foreground_session` is deliberately a separate event
        // rather than a property bolted onto this one: this edge also fires
        // for a background launch, where there is no visit to describe.
        let props = try #require(AppEnteredBackground(isPlaying: false).properties)
        #expect(props["is_playing"] as? Bool == false)
        #expect(props.count == 1)
    }
}
