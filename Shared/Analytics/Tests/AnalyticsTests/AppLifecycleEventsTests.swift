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
        #expect(props["duration_seconds"] as? Double == 12.5)
        #expect(props["is_playing"] as? Bool == true)
        #expect(props.count == 2)
        #expect(ForegroundSession.name == "foreground_session")
    }

    @Test(
        "A sub-second visit keeps its fractional seconds",
        arguments: [0.0, 0.25, 1.75, 3600.5]
    )
    func foregroundSessionKeepsFractionalSeconds(_ seconds: Double) throws {
        // The median visit is on the order of ten seconds, so truncating to
        // whole seconds — or to an Int — would quantize away most of the
        // distribution this event exists to measure.
        let props = try #require(ForegroundSession(durationSeconds: seconds, isPlaying: false).properties)
        #expect(props["duration_seconds"] as? Double == seconds)
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
