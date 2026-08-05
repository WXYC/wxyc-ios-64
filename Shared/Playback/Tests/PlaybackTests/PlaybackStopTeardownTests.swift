//
//  PlaybackStopTeardownTests.swift
//  Playback
//
//  Direct unit tests for the extracted `PlaybackStopTeardown` helper (#755) —
//  the six-step teardown sequence and #665 sessionID-survival rule shared by
//  AudioPlayerController and RadioPlayerController's `stop(reason:)`.
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import PlaybackCore

@Suite("PlaybackStopTeardown Tests")
struct PlaybackStopTeardownTests {

    @Test("Invokes cancelReconnect, resetBackoff, and stopHeartbeat exactly once")
    func invokesEachCallbackExactlyOnce() {
        var cancelReconnectCount = 0
        var resetBackoffCount = 0
        var stopHeartbeatCount = 0
        var playbackIntended = true
        var wasPlayingBeforeRouteDisconnect = false
        var sessionID: String? = "session-1"

        PlaybackStopTeardown.run(
            reason: .test,
            cancelReconnect: { cancelReconnectCount += 1 },
            resetBackoff: { resetBackoffCount += 1 },
            stopHeartbeat: { stopHeartbeatCount += 1 },
            playbackIntended: &playbackIntended,
            wasPlayingBeforeRouteDisconnect: &wasPlayingBeforeRouteDisconnect,
            sessionID: &sessionID
        )

        #expect(cancelReconnectCount == 1)
        #expect(resetBackoffCount == 1)
        #expect(stopHeartbeatCount == 1)
    }

    @Test("playbackIntended is always cleared, regardless of reason", arguments: [
        PlaybackReason.test, .interruptionBegan, .routeDisconnected, .remotePauseCommand
    ])
    func playbackIntendedAlwaysCleared(reason: PlaybackReason) {
        var playbackIntended = true
        var wasPlayingBeforeRouteDisconnect = false
        var sessionID: String? = nil

        PlaybackStopTeardown.run(
            reason: reason,
            cancelReconnect: {},
            resetBackoff: {},
            stopHeartbeat: {},
            playbackIntended: &playbackIntended,
            wasPlayingBeforeRouteDisconnect: &wasPlayingBeforeRouteDisconnect,
            sessionID: &sessionID
        )

        #expect(playbackIntended == false)
    }

    @Test("wasPlayingBeforeRouteDisconnect survives only a route-disconnected stop")
    func wasPlayingBeforeRouteDisconnectSurvivesOnlyRouteDisconnect() {
        // A route-disconnected stop must NOT clear it — the imminent
        // auto-resume on reconnect needs to know playback was active.
        var survivesFlag = true
        var playbackIntended = true
        var sessionID: String? = nil
        PlaybackStopTeardown.run(
            reason: .routeDisconnected,
            cancelReconnect: {},
            resetBackoff: {},
            stopHeartbeat: {},
            playbackIntended: &playbackIntended,
            wasPlayingBeforeRouteDisconnect: &survivesFlag,
            sessionID: &sessionID
        )
        #expect(survivesFlag == true, "routeDisconnected must preserve wasPlayingBeforeRouteDisconnect")

        // Any other reason clears it.
        var clearedFlag = true
        PlaybackStopTeardown.run(
            reason: .test,
            cancelReconnect: {},
            resetBackoff: {},
            stopHeartbeat: {},
            playbackIntended: &playbackIntended,
            wasPlayingBeforeRouteDisconnect: &clearedFlag,
            sessionID: &sessionID
        )
        #expect(clearedFlag == false, "A non-routeDisconnected stop must clear wasPlayingBeforeRouteDisconnect")
    }

    @Test("sessionID survives interruption and route-disconnect stops (#665)", arguments: [
        PlaybackReason.interruptionBegan, .routeDisconnected
    ])
    func sessionIDSurvivesInterruptionAndRouteDisconnect(reason: PlaybackReason) {
        var sessionID: String? = "session-1"
        var playbackIntended = true
        var wasPlayingBeforeRouteDisconnect = false

        PlaybackStopTeardown.run(
            reason: reason,
            cancelReconnect: {},
            resetBackoff: {},
            stopHeartbeat: {},
            playbackIntended: &playbackIntended,
            wasPlayingBeforeRouteDisconnect: &wasPlayingBeforeRouteDisconnect,
            sessionID: &sessionID
        )

        #expect(sessionID == "session-1", "sessionID must survive a \(reason) stop — it's a prelude to auto-resume, not the end of the listen")
    }

    @Test("sessionID is cleared for every other stop reason (#665)", arguments: [
        PlaybackReason.test, .remotePauseCommand, .remoteToggleCommand, .userTappedPlay
    ])
    func sessionIDClearedForGenuineStops(reason: PlaybackReason) {
        var sessionID: String? = "session-1"
        var playbackIntended = true
        var wasPlayingBeforeRouteDisconnect = false

        PlaybackStopTeardown.run(
            reason: reason,
            cancelReconnect: {},
            resetBackoff: {},
            stopHeartbeat: {},
            playbackIntended: &playbackIntended,
            wasPlayingBeforeRouteDisconnect: &wasPlayingBeforeRouteDisconnect,
            sessionID: &sessionID
        )

        #expect(sessionID == nil, "A genuine end-of-listen stop (\(reason)) must clear sessionID so the next play() mints a fresh id")
    }
}
