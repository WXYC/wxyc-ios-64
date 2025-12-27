//
//  PlaybackAnalyticsTests.swift
//  PlaybackTests
//
//  Tests for PlaybackAnalytics protocol and MockPlaybackAnalytics.
//

import Testing
import Foundation
@testable import PlaybackCore

@Suite("PlaybackAnalytics Tests")
struct PlaybackAnalyticsTests {

    // MARK: - MockPlaybackAnalytics Tests

    @Test("Mock captures playback started events")
    @MainActor
    func mockCapturesStarted() {
        let mock = MockPlaybackAnalytics()

        mock.capture(PlaybackStartedEvent(reason: .userInitiated))
        mock.capture(PlaybackStartedEvent(reason: .autoReconnect))

        #expect(mock.startedEvents.count == 2)
        #expect(mock.startedEvents[0].reason == .userInitiated)
        #expect(mock.startedEvents[1].reason == .autoReconnect)
    }

    @Test("Mock captures playback stopped events")
    @MainActor
    func mockCapturesStopped() {
        let mock = MockPlaybackAnalytics()

        mock.capture(PlaybackStoppedEvent(reason: .userInitiated, duration: 120.5))
        mock.capture(PlaybackStoppedEvent(reason: .stall, duration: 60.0))

        #expect(mock.stoppedEvents.count == 2)
        #expect(mock.stoppedEvents[0].reason == .userInitiated)
        #expect(mock.stoppedEvents[0].duration == 120.5)
        #expect(mock.stoppedEvents[1].reason == .stall)
        #expect(mock.stoppedEvents[1].duration == 60.0)
    }

    @Test("Mock captures stall recovery events")
    @MainActor
    func mockCapturesStallRecovery() {
        let mock = MockPlaybackAnalytics()

        mock.capture(StallRecoveryEvent(
            playerType: .radioPlayer,
            attempts: 3,
            stallDuration: 5.2
        ))

        #expect(mock.stallRecoveryEvents.count == 1)
        #expect(mock.stallRecoveryEvents[0].playerType == .radioPlayer)
        #expect(mock.stallRecoveryEvents[0].attempts == 3)
        #expect(mock.stallRecoveryEvents[0].stallDuration == 5.2)
    }

    @Test("Mock captures interruption events")
    @MainActor
    func mockCapturesInterruption() {
        let mock = MockPlaybackAnalytics()

        mock.capture(InterruptionEvent(type: .began))
        mock.capture(InterruptionEvent(type: .ended))

        #expect(mock.interruptionEvents.count == 2)
        #expect(mock.interruptionEvents[0].type == .began)
        #expect(mock.interruptionEvents[1].type == .ended)
    }

    @Test("Mock reset clears all captured events")
    @MainActor
    func mockResetClearsEvents() {
        let mock = MockPlaybackAnalytics()

        mock.capture(PlaybackStartedEvent(reason: .userInitiated))
        mock.capture(PlaybackStoppedEvent(reason: .userInitiated, duration: 100))
        mock.capture(StallRecoveryEvent(playerType: .radioPlayer, attempts: 1, stallDuration: 2.0))
        mock.capture(InterruptionEvent(type: .began))

        mock.reset()

        #expect(mock.startedEvents.isEmpty)
        #expect(mock.stoppedEvents.isEmpty)
        #expect(mock.stallRecoveryEvents.isEmpty)
        #expect(mock.interruptionEvents.isEmpty)
    }

    // MARK: - Sendable Tests

    @Test("Event types are Sendable", arguments: [
        PlaybackStartedEvent(reason: .userInitiated),
        PlaybackStartedEvent(reason: .autoReconnect),
        PlaybackStartedEvent(reason: .interruptionEnded),
        PlaybackStartedEvent(reason: .remoteCommand)
    ])
    func startedEventsAreSendable(event: PlaybackStartedEvent) async {
        await Task { @Sendable in _ = event }.value
    }

    @Test("Stopped events are Sendable", arguments: [
        PlaybackStoppedEvent(reason: .userInitiated, duration: 10.0),
        PlaybackStoppedEvent(reason: .stall, duration: 5.0),
        PlaybackStoppedEvent(reason: .interruptionBegan, duration: 100.0),
        PlaybackStoppedEvent(reason: .error(.unknown("test")), duration: 1.0)
    ])
    func stoppedEventsAreSendable(event: PlaybackStoppedEvent) async {
        await Task { @Sendable in _ = event }.value
    }

    @Test("Stall recovery events are Sendable", arguments: [
        StallRecoveryEvent(playerType: .radioPlayer, attempts: 1, stallDuration: 1.0),
        StallRecoveryEvent(playerType: .avAudioStreamer, attempts: 5, stallDuration: 10.0)
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
}
