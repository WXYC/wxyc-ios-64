//
//  FirstAudioAnalyticsTests.swift
//  Playback
//
//  Verifies the controller forwards a player's `.firstAudio` internal event into a
//  `PlaybackFirstAudioEvent` analytics capture — the playback-start success signal
//  paired with the `play` intent count to compute a start-success rate (issue #513).
//
//  Created by Jake Bromberg on 07/14/26.
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

@Suite("First Audio Analytics")
@MainActor
struct FirstAudioAnalyticsTests {

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

    private func firstAudioEvents(_ analytics: MockStructuredAnalytics) -> [PlaybackFirstAudioEvent] {
        analytics.typedEvents(ofType: PlaybackFirstAudioEvent.self)
    }

    @Test("Controller captures PlaybackFirstAudioEvent when player reports first audio")
    func capturesFirstAudioEvent() async throws {
        let (controller, mockPlayer, mockAnalytics) = makeHarness()
        controller.play(reason: .test)
        mockAnalytics.reset()

        mockPlayer.simulateFirstAudio(timeToAudio: 1.4)

        // Drain the controller's event-observer task.
        for _ in 0..<32 { await Task.yield() }

        let events = firstAudioEvents(mockAnalytics)
        #expect(events.count == 1, "One firstAudio event should be captured")
        let event = try #require(events.first)
        #expect(event.playerType == .mp3Streamer)
        #expect(event.timeToFirstAudio == 1.4)

        let props = try #require(event.properties)
        #expect(props["time_to_first_audio"] as? TimeInterval == 1.4)
        #expect(props["player_type"] as? String == PlayerControllerType.mp3Streamer.rawValue)
    }

    @Test("PlaybackFirstAudioEvent is named first_audio for PostHog")
    func eventNameIsFirstAudio() {
        #expect(PlaybackFirstAudioEvent.name == "first_audio")
    }

    @Test("A player error does not produce a firstAudio event")
    func errorDoesNotProduceFirstAudio() async throws {
        let (controller, mockPlayer, mockAnalytics) = makeHarness()
        controller.play(reason: .test)
        mockAnalytics.reset()

        mockPlayer.simulateError(TestStreamError.networkFailure)
        for _ in 0..<32 { await Task.yield() }

        #expect(firstAudioEvents(mockAnalytics).isEmpty,
                "A failure must not be counted as a successful start")
    }
}

#endif // os(iOS) || os(tvOS)
