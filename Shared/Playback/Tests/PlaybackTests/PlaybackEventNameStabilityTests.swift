//
//  PlaybackEventNameStabilityTests.swift
//  Playback
//
//  Parameterized tests pinning the play/pause event names so a future rename
//  can't silently zero the "Play/Pause Counts" and duration dashboards.
//  Mirrors Analytics/Tests/AnalyticsTests/EventNameStabilityTests.swift.
//
//  Created by Jake Bromberg on 07/25/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import PlaybackCore

private let expectedPlaybackEventNames: [(String, String)] = [
    (PlaybackStartedEvent.name, "play"),
    (PlaybackStoppedEvent.name, "pause"),
]

@Suite("Playback Event Name Stability")
struct PlaybackEventNameStabilityTests {

    @Test("Playback event names are stable", arguments: expectedPlaybackEventNames)
    func playbackEventNameIsStable(actual: String, expected: String) {
        #expect(actual == expected)
    }
}
