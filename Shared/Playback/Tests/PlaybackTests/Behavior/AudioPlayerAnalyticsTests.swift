//
//  AudioPlayerAnalyticsTests.swift
//  Playback
//
//  Analytics capture tests for all AudioPlayerProtocol implementations.
//  Verifies that MP3Streamer and RadioPlayer have identical analytics behavior.
//
//  Created by Jake Bromberg on 01/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import PlaybackTestUtilities
import AnalyticsTesting
import Analytics
import AVFoundation
@testable import PlaybackCore
@testable import RadioPlayerModule
#if !os(watchOS)
@testable import MP3StreamerModule
#endif

// MARK: - AudioPlayer Analytics Integration Tests

@Suite("AudioPlayer Analytics Tests")
@MainActor
struct AudioPlayerAnalyticsTests {

    @Test("play() calls analytics", arguments: AudioPlayerTestCase.allCases)
    func playCallsAnalytics(testCase: AudioPlayerTestCase) async throws {
        let harness = AudioPlayerTestHarness.make(for: testCase)
        harness.mockAnalytics.reset()

        harness.player.play()

        // Wait for async operations
        await harness.waitForAsync()

        let startedEvents = harness.mockAnalytics.events.compactMap { $0 as? PlaybackStartedEvent }
        #expect(!startedEvents.isEmpty, "play() should call analytics with PlaybackStartedEvent")
    }

    @Test("play() captures specific event name", arguments: AudioPlayerTestCase.allCases)
    func playCapturesSpecificEventName(testCase: AudioPlayerTestCase) async throws {
        let harness = AudioPlayerTestHarness.make(for: testCase)
        harness.mockAnalytics.reset()

        harness.player.play()
        await harness.waitForAsync()

        let startedEvents = harness.mockAnalytics.events.compactMap { $0 as? PlaybackStartedEvent }
        #expect(!startedEvents.isEmpty)
        let event = startedEvents.first
        
        switch testCase {
        #if !os(watchOS)
        case .mp3Streamer:
            #expect(event?.reason == "mp3Streamer play",
                   "MP3Streamer should capture 'mp3Streamer play' reason")
        #endif
        case .radioPlayer:
            #expect(event?.reason == "radioPlayer play",
                   "RadioPlayer should capture 'radioPlayer play' reason")
        }
    }

    @Test("play() when already playing captures 'already playing' event", arguments: AudioPlayerTestCase.allCases)
    func playWhenAlreadyPlayingCapturesEvent(testCase: AudioPlayerTestCase) async throws {
        let harness = AudioPlayerTestHarness.make(for: testCase)

        // Start playing first
        harness.player.play()
        await harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        // Verify we're actually in playing state before testing "already playing" behavior
        guard harness.player.state == .playing else {
            // Skip test if player couldn't reach playing state (e.g., MP3Streamer in CI without audio hardware)
            return
        }

        // Reset analytics to capture only the second play call
        harness.mockAnalytics.reset()

        // Call play again while already playing
        harness.player.play()
        await harness.waitForAsync()

        let startedEvents = harness.mockAnalytics.events.compactMap { $0 as? PlaybackStartedEvent }
        let alreadyPlayingEvent = startedEvents.first { $0.reason.contains("already playing") }

        #expect(alreadyPlayingEvent != nil,
               "play() while already playing should capture 'already playing' event")
    }

    /// The playback-start success signal (issue #513): MP3Streamer must yield exactly
    /// one `.firstAudio` internal event when it first reaches `.playing`, carrying a
    /// non-negative time-to-first-audio. The controller forwards this as a
    /// `PlaybackFirstAudioEvent`; that forwarding is covered in `FirstAudioAnalyticsTests`.
    /// RadioPlayer does not emit it, so the assertion is scoped to MP3Streamer.
    @Test("First audio internal event fires once on a healthy start", arguments: AudioPlayerTestCase.allCases)
    func firstAudioInternalEventFires(testCase: AudioPlayerTestCase) async throws {
        let harness = AudioPlayerTestHarness.make(for: testCase)

        final class Collector { var times: [TimeInterval] = [] }
        let collector = Collector()
        let drain = Task { @MainActor in
            for await event in harness.player.eventStream {
                if case .firstAudio(let timeToAudio) = event {
                    collector.times.append(timeToAudio)
                }
            }
        }
        defer { drain.cancel() }

        harness.player.play()
        await harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        // Give the event stream a moment to deliver.
        try await Task.sleep(for: .milliseconds(50))

        switch testCase {
        #if !os(watchOS)
        case .mp3Streamer:
            // Only assert when the environment actually reached .playing (CI without
            // audio decode can't); otherwise the signal legitimately never fires.
            guard harness.player.state == .playing else { return }
            #expect(collector.times.count == 1, "Exactly one first-audio event on a healthy MP3Streamer start")
            if let time = collector.times.first {
                #expect(time >= 0, "time-to-first-audio must be non-negative")
            }
        #endif
        case .radioPlayer:
            #expect(collector.times.isEmpty, "RadioPlayer does not emit a first-audio internal event")
        }
    }

    @Test("Multiple plays accumulate analytics events", arguments: AudioPlayerTestCase.allCases)
    func multiplePlaysCaptureMultipleEvents(testCase: AudioPlayerTestCase) async throws {
        let harness = AudioPlayerTestHarness.make(for: testCase)
        harness.mockAnalytics.reset()

        // First play
        harness.player.play()
        await harness.waitForAsync()
        try await Task.sleep(for: .milliseconds(100))

        // Verify first play was captured
        let firstPlayEvents = harness.mockAnalytics.capturedEventNames().filter { $0.contains("play") && !$0.contains("already") }
        #expect(firstPlayEvents.count >= 1, "First play() should capture analytics")

        // Stop and wait for state to settle
        harness.player.stop()
        await harness.waitForAsync()
        try await Task.sleep(for: .milliseconds(100))

        // Second play
        harness.player.play()
        await harness.waitForAsync()
        try await Task.sleep(for: .milliseconds(100))

        let allPlayEvents = harness.mockAnalytics.events.compactMap { $0 as? PlaybackStartedEvent }.filter { !$0.reason.contains("already") }
        #expect(allPlayEvents.count >= 2, "Should capture play events for each play() call")
    }

    @Test("Analytics work without errors when nil", arguments: AudioPlayerTestCase.allCases)
    func analyticsWorkWithNilService(testCase: AudioPlayerTestCase) async throws {
        // Create player without analytics
        let notificationCenter = NotificationCenter()

        switch testCase {
        #if !os(watchOS)
        case .mp3Streamer:
            let config = MP3StreamerConfiguration(
                url: URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!
            )
            let streamer = MP3Streamer(
                configuration: config,
                analytics: nil // No analytics
            )

            // Should not crash
            streamer.play()
            try await Task.sleep(for: .milliseconds(50))
            streamer.stop()
        #endif

        case .radioPlayer:
            let mockPlayer = MockPlayer(autoSetRateOnPlay: false)
            let radioPlayer = RadioPlayer(
                player: mockPlayer,
                analytics: nil, // No analytics
                notificationCenter: notificationCenter
            )

            // Should not crash
            radioPlayer.play()
            try await Task.sleep(for: .milliseconds(50))
        }

        // If we got here without crashing, test passes
        #expect(true)
    }
}

#if !os(watchOS)
// MARK: - MP3Streamer-Specific Analytics Tests

@Suite("MP3Streamer Analytics Tests")
@MainActor
struct MP3StreamerAnalyticsTests {

    @Test("MP3Streamer captures play event on initial connect")
    func capturesPlayOnConnect() async throws {
        let mockAnalytics = MockStructuredAnalytics()
        let mockHTTPClient = MockHTTPStreamClient()
        let mockAudioEngine = MockAudioEnginePlayer()

        let config = MP3StreamerConfiguration(
            url: URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!
        )
        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTPClient,
            audioPlayer: mockAudioEngine,
            analytics: mockAnalytics
        )

        streamer.play()
        try await Task.sleep(for: .milliseconds(50))

        let events = mockAnalytics.events.compactMap { $0 as? PlaybackStartedEvent }
        #expect(events.contains { $0.reason == "mp3Streamer play" })
    }

    @Test("MP3Streamer captures already playing when play called twice")
    func capturesAlreadyPlaying() async throws {
        let mockAnalytics = MockStructuredAnalytics()
        let mockHTTPClient = MockHTTPStreamClient()
        let mockAudioEngine = MockAudioEnginePlayer()

        // Load test data so it can reach playing state
        if let testData = try? TestAudioBufferFactory.loadMP3TestData() {
            mockHTTPClient.testData = testData
        }

        let config = MP3StreamerConfiguration(
            url: URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!,
            minimumBuffersBeforePlayback: 2
        )
        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTPClient,
            audioPlayer: mockAudioEngine,
            analytics: mockAnalytics
        )

        streamer.play()

        // Wait for state to reach playing
        var attempts = 0
        while streamer.state != .playing && attempts < 20 {
            try await Task.sleep(for: .milliseconds(50))
            attempts += 1
        }
        
        // Reset and call play again
        // Note: Time to first Audio might be captured late, so we don't strict-reset if it races,
        // but we definitely want to ensure we're playing first.
        mockAnalytics.reset()
        streamer.play()
        try await Task.sleep(for: .milliseconds(50))

        let events = mockAnalytics.events.compactMap { $0 as? PlaybackStartedEvent }
        #expect(events.contains { $0.reason.contains("already playing") })
    }
}

// MARK: - AudioEnginePlayer Analytics Tests

@Suite(
    "AudioEnginePlayer Analytics Tests",
    .tags(.e2e),
    .disabled(if: ProcessInfo.processInfo.environment["RUN_E2E"] != "1", "Real AVAudioEngine — opt in with RUN_E2E=1")
)
@MainActor
struct AudioEnginePlayerAnalyticsTests {

    @Test("AudioEnginePlayer captures play event")
    func capturesPlayEvent() async throws {
        let mockAnalytics = MockStructuredAnalytics()
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format, analytics: mockAnalytics)
        player.volume = 0  // silence test output

        try player.play()

        let events = mockAnalytics.events.compactMap { $0 as? PlaybackStartedEvent }
        #expect(events.contains { $0.reason == "audioEnginePlayer play" })

        player.stop()
    }

    @Test("AudioEnginePlayer captures already playing when play called twice")
    func capturesAlreadyPlaying() async throws {
        let mockAnalytics = MockStructuredAnalytics()
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format, analytics: mockAnalytics)
        player.volume = 0  // silence test output

        try player.play()
        mockAnalytics.reset()

        try player.play() // Second call while playing

        let events = mockAnalytics.events.compactMap { $0 as? PlaybackStartedEvent }
        #expect(events.contains { $0.reason.contains("already playing") })

        player.stop()
    }

    @Test("AudioEnginePlayer captures pause event")
    func capturesPauseEvent() async throws {
        let mockAnalytics = MockStructuredAnalytics()
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format, analytics: mockAnalytics)
        player.volume = 0  // silence test output

        try player.play()
        mockAnalytics.reset()

        player.pause()

        let events = mockAnalytics.events.compactMap { $0 as? PlaybackStoppedEvent }
        #expect(events.contains { $0.reason == "audioEnginePlayer pause" })

        player.stop()
    }

    @Test("AudioEnginePlayer captures stop event")
    func capturesStopEvent() async throws {
        let mockAnalytics = MockStructuredAnalytics()
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format, analytics: mockAnalytics)
        player.volume = 0  // silence test output

        try player.play()
        mockAnalytics.reset()

        player.stop()

        let events = mockAnalytics.events.compactMap { $0 as? PlaybackStoppedEvent }
        #expect(events.contains { $0.reason == "audioEnginePlayer stop" })
    }

    @Test("AudioEnginePlayer works without analytics")
    func worksWithoutAnalytics() async throws {
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format, analytics: nil)
        player.volume = 0  // silence test output

        // Should not crash
        try player.play()
        player.pause()
        try player.play()
        player.stop()

        #expect(true) // If we got here without crashing, test passes
    }
}
#endif

// MARK: - Test Tags

extension Tag {
    @Tag static var e2e: Self
}
