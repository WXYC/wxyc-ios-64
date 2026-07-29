//
//  ExtendedOfflineParkAnalyticsTests.swift
//  Playback
//
//  Verifies the controller forwards a player's `.extendedOfflinePark` internal
//  event into an `ExtendedOfflineParkEvent` analytics capture — the low-rate
//  observability signal for a sustained offline connect park that #697's
//  startup-watchdog gate deliberately excludes from `startup_timeout`/
//  `stream_error` (issue #699).
//
//  Created by Jake Bromberg on 07/28/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import PlaybackTestUtilities
import AnalyticsTesting
import Analytics
import AVFoundation
import Core
@testable import Playback
@testable import PlaybackCore

#if os(iOS) || os(tvOS)

@Suite("Extended Offline Park Analytics")
@MainActor
struct ExtendedOfflineParkAnalyticsTests {

    private func makeHarness() -> (AudioPlayerController, MockAudioPlayer, MockStructuredAnalytics) {
        let streamURL = URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!
        let mockPlayer = MockAudioPlayer(url: streamURL)
        let mockAnalytics = MockStructuredAnalytics()
        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: MockAudioSession(),
            remoteCommandCenter: MockRemoteCommandCenter(),
            notificationCenter: NotificationCenter(),
            analytics: mockAnalytics
        )
        return (controller, mockPlayer, mockAnalytics)
    }

    private func parkEvents(_ analytics: MockStructuredAnalytics) -> [ExtendedOfflineParkEvent] {
        analytics.typedEvents(ofType: ExtendedOfflineParkEvent.self)
    }

    @Test("Controller captures ExtendedOfflineParkEvent when player reports an extended park")
    func capturesExtendedOfflineParkEvent() async throws {
        let (controller, mockPlayer, mockAnalytics) = makeHarness()
        controller.play(reason: .test)
        mockAnalytics.reset()

        mockPlayer.simulateExtendedOfflinePark(duration: 24.5)

        // Drain the controller's event-observer task.
        for _ in 0..<32 { await Task.yield() }

        let events = parkEvents(mockAnalytics)
        #expect(events.count == 1, "One extendedOfflinePark event should be captured")
        let event = try #require(events.first)
        #expect(event.playerType == .mp3Streamer)
        #expect(event.parkDuration == 24.5)

        let props = try #require(event.properties)
        #expect(props["park_duration"] as? TimeInterval == 24.5)
        #expect(props["player_type"] as? String == PlayerControllerType.mp3Streamer.rawValue)
    }

    @Test("ExtendedOfflineParkEvent is named extended_offline_park for PostHog")
    func eventNameIsExtendedOfflinePark() {
        #expect(ExtendedOfflineParkEvent.name == "extended_offline_park")
    }

    /// #697's whole point is that a legitimately offline park is NOT a stream
    /// error; #699 must not regress that by pairing its own signal with one.
    @Test("An extended offline park does not also produce a StreamErrorEvent")
    func extendedOfflineParkDoesNotProduceStreamError() async throws {
        let (controller, mockPlayer, mockAnalytics) = makeHarness()
        controller.play(reason: .test)
        mockAnalytics.reset()

        mockPlayer.simulateExtendedOfflinePark(duration: 24.5)
        for _ in 0..<32 { await Task.yield() }

        #expect(mockAnalytics.typedEvents(ofType: StreamErrorEvent.self).isEmpty,
                "An extended offline park is a distinct observability signal, not a stream error — #697's exclusion must hold")
    }

    @Test("A normal first-audio success does not produce an extendedOfflinePark event")
    func firstAudioDoesNotProduceExtendedOfflinePark() async throws {
        let (controller, mockPlayer, mockAnalytics) = makeHarness()
        controller.play(reason: .test)
        mockAnalytics.reset()

        mockPlayer.simulateFirstAudio(timeToAudio: 1.4)
        for _ in 0..<32 { await Task.yield() }

        #expect(parkEvents(mockAnalytics).isEmpty)
    }
}

#endif // os(iOS) || os(tvOS)
