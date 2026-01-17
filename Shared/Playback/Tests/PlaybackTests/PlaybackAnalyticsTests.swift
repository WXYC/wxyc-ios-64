//
//  PlaybackAnalyticsTests.swift
//  Playback
//
//  Tests for PlaybackAnalytics protocol and MockPlaybackAnalytics.
//
//  Created by Jake Bromberg on 12/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Testing
import PlaybackTestUtilities
import AnalyticsTesting
import Foundation
@testable import PlaybackCore

@Suite("PlaybackAnalytics Tests")
struct PlaybackAnalyticsTests {

    // MARK: - MockPlaybackAnalytics Tests

    @Test("Mock captures playback started events")
    @MainActor
    func mockCapturesStarted() {
        let mock = MockStructuredAnalytics()

        mock.capture(PlaybackStartedEvent(reason: "user initiated"))
        mock.capture(PlaybackStartedEvent(reason: "auto reconnect"))
        
        let startedEvents = mock.events.compactMap { $0 as? PlaybackStartedEvent }

        #expect(startedEvents.count == 2)
        #expect(startedEvents[0].reason == "user initiated")
        #expect(startedEvents[1].reason == "auto reconnect")
    }

    @Test("Mock captures playback stopped events")
    @MainActor
    func mockCapturesStopped() {
        let mock = MockStructuredAnalytics()

        mock.capture(PlaybackStoppedEvent(duration: 120.5))
        mock.capture(PlaybackStoppedEvent(reason: "stall", duration: 60.0))
        
        let stoppedEvents = mock.events.compactMap { $0 as? PlaybackStoppedEvent }

        #expect(stoppedEvents.count == 2)
        #expect(stoppedEvents[0].reason == nil)
        #expect(stoppedEvents[0].duration == 120.5)
        #expect(stoppedEvents[1].reason == "stall")
        #expect(stoppedEvents[1].duration == 60.0)
    }

    @Test("Mock captures stall recovery events")
    @MainActor
    func mockCapturesStallRecovery() {
        let mock = MockStructuredAnalytics()

        mock.capture(StallRecoveryEvent(
            playerType: .radioPlayer,
            attempts: 3,
            stallDuration: 5.2
        ))
        
        let stallRecoveryEvents = mock.events.compactMap { $0 as? StallRecoveryEvent }

        #expect(stallRecoveryEvents.count == 1)
        #expect(stallRecoveryEvents[0].playerType == .radioPlayer)
        #expect(stallRecoveryEvents[0].attempts == 3)
        #expect(stallRecoveryEvents[0].stallDuration == 5.2)
    }

    @Test("Mock captures stream error events")
    @MainActor
    func mockCapturesStreamError() {
        let mock = MockStructuredAnalytics()

        mock.capture(StreamErrorEvent(
            playerType: .mp3Streamer,
            errorType: .backoffExhausted,
            errorDescription: "Max attempts exceeded",
            reconnectAttempts: 10,
            sessionDuration: 120.5,
            stallDuration: 5.0,
            recoveryMethod: .retryWithBackoff
        ))

        let streamErrorEvents = mock.events.compactMap { $0 as? StreamErrorEvent }

        #expect(streamErrorEvents.count == 1)
        #expect(streamErrorEvents[0].playerType == .mp3Streamer)
        #expect(streamErrorEvents[0].errorType == .backoffExhausted)
        #expect(streamErrorEvents[0].errorDescription == "Max attempts exceeded")
        #expect(streamErrorEvents[0].reconnectAttempts == 10)
        #expect(streamErrorEvents[0].sessionDuration == 120.5)
        #expect(streamErrorEvents[0].stallDuration == 5.0)
        #expect(streamErrorEvents[0].recoveryMethod == .retryWithBackoff)
    }

    @Test("Stream error event without stall duration")
    @MainActor
    func streamErrorWithoutStallDuration() {
        let mock = MockStructuredAnalytics()

        mock.capture(StreamErrorEvent(
            playerType: .radioPlayer,
            errorType: .networkError,
            errorDescription: "Network connection failed",
            reconnectAttempts: 3,
            sessionDuration: 60.0
        ))

        let streamErrorEvents = mock.events.compactMap { $0 as? StreamErrorEvent }

        #expect(streamErrorEvents.count == 1)
        #expect(streamErrorEvents[0].stallDuration == nil)
        #expect(streamErrorEvents[0].recoveryMethod == .retryWithBackoff) // default
    }

    @Test("Mock captures interruption events")
    @MainActor
    func mockCapturesInterruption() {
        let mock = MockStructuredAnalytics()

        mock.capture(InterruptionEvent(type: .began))
        mock.capture(InterruptionEvent(type: .ended))
        
        let interruptionEvents = mock.events.compactMap { $0 as? InterruptionEvent }

        #expect(interruptionEvents.count == 2)
        #expect(interruptionEvents[0].type == .began)
        #expect(interruptionEvents[1].type == .ended)
    }

    @Test("Mock reset clears all captured events")
    @MainActor
    func mockResetClearsEvents() {
        let mock = MockStructuredAnalytics()

        mock.capture(PlaybackStartedEvent(reason: "user initiated"))
        mock.capture(PlaybackStoppedEvent(duration: 100))
        mock.capture(StallRecoveryEvent(playerType: .radioPlayer, attempts: 1, stallDuration: 2.0))
        mock.capture(InterruptionEvent(type: .began))

        mock.reset()

        #expect(mock.events.isEmpty)
    }

    // MARK: - Sendable Tests

    @Test("Event types are Sendable", arguments: [
        PlaybackStartedEvent(reason: "user initiated"),
        PlaybackStartedEvent(reason: "auto reconnect"),
        PlaybackStartedEvent(reason: "interruption ended"),
        PlaybackStartedEvent(reason: "remote command")
    ])
    func startedEventsAreSendable(event: PlaybackStartedEvent) async {
        await Task { @Sendable in _ = event }.value
    }

    @Test("Stopped events are Sendable", arguments: [
        PlaybackStoppedEvent(duration: 10.0),
        PlaybackStoppedEvent(reason: "stall", duration: 5.0),
        PlaybackStoppedEvent(reason: "interruption began", duration: 100.0),
        PlaybackStoppedEvent(reason: "error", duration: 1.0)
    ])
    func stoppedEventsAreSendable(event: PlaybackStoppedEvent) async {
        await Task { @Sendable in _ = event }.value
    }

    @Test("Stall recovery events are Sendable", arguments: [
        StallRecoveryEvent(playerType: .radioPlayer, attempts: 1, stallDuration: 1.0),
        StallRecoveryEvent(playerType: .mp3Streamer, attempts: 5, stallDuration: 10.0)
    ])
    func stallRecoveryEventsAreSendable(event: StallRecoveryEvent) async {
        await Task { @Sendable in _ = event }.value
    }

    @Test("Interruption events are Sendable", arguments: [
        InterruptionEvent(type: .began),
        InterruptionEvent(type: .ended),
        InterruptionEvent(type: .routeDisconnected)
    ])
    func interruptionEventsAreSendable(event: InterruptionEvent) async {
        await Task { @Sendable in _ = event }.value
    }

    @Test("Stream error events are Sendable", arguments: [
        StreamErrorEvent(
            playerType: .radioPlayer,
            errorType: .backoffExhausted,
            errorDescription: "Backoff exhausted",
            reconnectAttempts: 10,
            sessionDuration: 60.0
        ),
        StreamErrorEvent(
            playerType: .mp3Streamer,
            errorType: .networkError,
            errorDescription: "Network failed",
            reconnectAttempts: 3,
            sessionDuration: 30.0,
            stallDuration: 5.0
        )
    ])
    func streamErrorEventsAreSendable(event: StreamErrorEvent) async {
        await Task { @Sendable in _ = event }.value
    }

    @Test("StreamErrorType raw values", arguments: [
        (StreamErrorType.backoffExhausted, "backoff_exhausted"),
        (StreamErrorType.networkError, "network_error"),
        (StreamErrorType.decodingError, "decoding_error"),
        (StreamErrorType.playerError, "player_error"),
        (StreamErrorType.unknown, "unknown")
    ])
    func streamErrorTypeRawValues(errorType: StreamErrorType, expectedRawValue: String) {
        #expect(errorType.rawValue == expectedRawValue)
    }
}
