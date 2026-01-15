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

        let eventNames = harness.mockAnalytics.capturedEventNames()
        #expect(eventNames.contains { $0.contains("play") }, "play() should call analytics")
    }

    @Test("play() captures specific event name", arguments: AudioPlayerTestCase.allCases)
    func playCapturesSpecificEventName(testCase: AudioPlayerTestCase) async throws {
        let harness = AudioPlayerTestHarness.make(for: testCase)
        harness.mockAnalytics.reset()

        harness.player.play()
        await harness.waitForAsync()

        let eventNames = harness.mockAnalytics.capturedEventNames()

        switch testCase {
        #if !os(watchOS)
        case .mp3Streamer:
            #expect(eventNames.contains("mp3Streamer play"),
                   "MP3Streamer should capture 'mp3Streamer play' event")
        #endif
        case .radioPlayer:
            #expect(eventNames.contains("radioPlayer play"),
                   "RadioPlayer should capture 'radioPlayer play' event")
        }
    }

    @Test("play() when already playing captures 'already playing' event", arguments: AudioPlayerTestCase.allCases)
    func playWhenAlreadyPlayingCapturesEvent(testCase: AudioPlayerTestCase) async throws {
        let harness = AudioPlayerTestHarness.make(for: testCase)

        // Start playing first
        harness.player.play()
        await harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        // Reset analytics to capture only the second play call
        harness.mockAnalytics.reset()

        // Call play again while already playing
        harness.player.play()
        await harness.waitForAsync()

        let eventNames = harness.mockAnalytics.capturedEventNames()
        #expect(eventNames.contains { $0.contains("already playing") },
               "play() while already playing should capture 'already playing' event")
    }

    @Test("Time to first Audio is captured on playback start", arguments: AudioPlayerTestCase.allCases)
    func timeToFirstAudioCaptured(testCase: AudioPlayerTestCase) async throws {
        let harness = AudioPlayerTestHarness.make(for: testCase)
        harness.mockAnalytics.reset()

        harness.player.play()
        await harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        let timeToAudioEvent = harness.mockAnalytics.capturedEvent(named: "Time to first Audio")
        #expect(timeToAudioEvent != nil, "Should capture 'Time to first Audio' event")

        if let event = timeToAudioEvent {
            #expect(event.properties?["timeToAudio"] != nil,
                   "'Time to first Audio' event should include timeToAudio property")
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

        let allPlayEvents = harness.mockAnalytics.capturedEventNames().filter { $0.contains("play") && !$0.contains("already") }
        #expect(allPlayEvents.count >= 2, "Should capture play events for each play() call, but got \(allPlayEvents)")
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
        let mockAnalytics = MockAnalyticsService()
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

        #expect(mockAnalytics.capturedEventNames().contains("mp3Streamer play"))
    }

    @Test("MP3Streamer captures already playing when play called twice")
    func capturesAlreadyPlaying() async throws {
        let mockAnalytics = MockAnalyticsService()
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

        #expect(mockAnalytics.capturedEventNames().contains("mp3Streamer already playing"))
    }
}

// MARK: - AudioEnginePlayer Analytics Tests

@Suite("AudioEnginePlayer Analytics Tests")
@MainActor
struct AudioEnginePlayerAnalyticsTests {

    @Test("AudioEnginePlayer captures play event")
    func capturesPlayEvent() async throws {
        let mockAnalytics = MockAnalyticsService()
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format, analytics: mockAnalytics)

        try player.play()

        #expect(mockAnalytics.capturedEventNames().contains("audioEnginePlayer play"))

        player.stop()
    }

    @Test("AudioEnginePlayer captures already playing when play called twice")
    func capturesAlreadyPlaying() async throws {
        let mockAnalytics = MockAnalyticsService()
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format, analytics: mockAnalytics)

        try player.play()
        mockAnalytics.reset()

        try player.play() // Second call while playing

        #expect(mockAnalytics.capturedEventNames().contains("audioEnginePlayer already playing"))

        player.stop()
    }

    @Test("AudioEnginePlayer captures pause event")
    func capturesPauseEvent() async throws {
        let mockAnalytics = MockAnalyticsService()
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format, analytics: mockAnalytics)

        try player.play()
        mockAnalytics.reset()

        player.pause()

        #expect(mockAnalytics.capturedEventNames().contains("audioEnginePlayer pause"))

        player.stop()
    }

    @Test("AudioEnginePlayer captures stop event")
    func capturesStopEvent() async throws {
        let mockAnalytics = MockAnalyticsService()
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format, analytics: mockAnalytics)

        try player.play()
        mockAnalytics.reset()

        player.stop()

        #expect(mockAnalytics.capturedEventNames().contains("audioEnginePlayer stop"))
    }

    @Test("AudioEnginePlayer works without analytics")
    func worksWithoutAnalytics() async throws {
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format, analytics: nil)

        // Should not crash
        try player.play()
        player.pause()
        try player.play()
        player.stop()

        #expect(true) // If we got here without crashing, test passes
    }
}
#endif
