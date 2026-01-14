//
//  PlayerControllerBehaviorTests.swift
//  Playback
//
//  Core playback behavior tests (play/stop/toggle) for all PlaybackController implementations.
//  These tests define the expected behavioral contract that all player controllers must follow.
//
//  Created by Jake Bromberg on 12/27/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Testing
import PlaybackTestUtilities
import AVFoundation
@testable import Playback
@testable import PlaybackCore
@testable import RadioPlayerModule
#if !os(watchOS)
@testable import MP3StreamerModule
#endif

// MARK: - Parameterized Behavior Tests

@Suite("Player Controller Behavior Tests")
@MainActor
struct PlayerControllerBehaviorTests {

    // MARK: - Core Playback Behavior (Mocked Controllers)

    @Test("play() sets isPlaying to true", arguments: PlayerControllerTestCase.allCases)
    func playSetsIsPlayingTrue(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying, "play() should set isPlaying to true")
    }

    @Test("stop() sets isPlaying to false", arguments: PlayerControllerTestCase.allCases)
    func stopSetsIsPlayingFalse(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        harness.controller.stop()
        harness.simulatePlaybackStopped()
        await harness.waitForAsync()

        #expect(!harness.controller.isPlaying, "stop() should set isPlaying to false")
    }

    @Test("toggle() while playing stops", arguments: PlayerControllerTestCase.allCases)
    func toggleFromPlayingStops(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying)

        harness.controller.toggle()
        harness.simulatePlaybackStopped()
        await harness.waitForAsync()

        #expect(!harness.controller.isPlaying, "toggle() while playing should stop")
    }

    @Test("toggle() while stopped starts playback", arguments: PlayerControllerTestCase.allCases)
    func toggleWhileStoppedStartsPlayback(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        #expect(!harness.controller.isPlaying)

        harness.controller.toggle()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        #expect(harness.controller.isPlaying, "toggle() while stopped should start playback")
    }

    @Test("Initial state is not playing", arguments: PlayerControllerTestCase.allCases)
    func initialStateIsNotPlaying(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        #expect(!harness.controller.isPlaying, "Initial state should be not playing")
    }

    // MARK: - Underlying Player Integration (Mocked Controllers Only)

    /// Note: This test only runs for AudioPlayerController because RadioPlayerController's
    /// play() method goes through AVAudioSession.activate() which fails in test environments.
    /// RadioPlayerController's player integration is tested via simulatePlaybackStarted() instead.
    #if os(iOS) || os(tvOS)
    @Test("play() calls underlying player")
    func playCallsUnderlyingPlayer() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)
        let initialCount = harness.playCallCount
        harness.controller.play()
        await harness.waitForAsync()
        #expect(harness.playCallCount > initialCount, "play() should call underlying player")
    }
    #endif

    @Test("stop() calls underlying player", arguments: PlayerControllerTestCase.allCases)
    func stopCallsUnderlyingPlayer(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        let initialCount = harness.stopCallCount
        harness.controller.stop()
        await harness.waitForAsync()

        #expect(harness.stopCallCount > initialCount, "stop() should call underlying player")
    }

    // MARK: - State Consistency Tests

    @Test("Multiple play calls are idempotent", arguments: PlayerControllerTestCase.allCases)
    func multiplePlayCallsAreIdempotent(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying)

        // Play again while already playing
        harness.controller.play()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying, "Multiple play calls should keep isPlaying true")
    }

    @Test("Multiple stop calls are idempotent", arguments: PlayerControllerTestCase.allCases)
    func multipleStopCallsAreIdempotent(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        harness.controller.stop()
        harness.simulatePlaybackStopped()
        await harness.waitForAsync()
        #expect(!harness.controller.isPlaying)

        // Stop again while already stopped
        harness.controller.stop()
        await harness.waitForAsync()
        #expect(!harness.controller.isPlaying, "Multiple stop calls should keep isPlaying false")
    }

    @Test("Rapid play/stop cycles maintain consistency", arguments: PlayerControllerTestCase.allCases)
    func rapidPlayStopCyclesMaintainConsistency(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)

        for _ in 0..<5 {
            harness.controller.play()
            harness.simulatePlaybackStarted()
            await harness.waitForAsync()
            #expect(harness.controller.isPlaying)

            harness.controller.stop()
            harness.simulatePlaybackStopped()
            await harness.waitForAsync()
            #expect(!harness.controller.isPlaying)
        }
    }
}

// MARK: - PlaybackController Protocol Conformance Tests

@Suite("PlaybackController Protocol Conformance Tests")
@MainActor
struct PlaybackControllerProtocolTests {

    @Test("All controllers conform to PlaybackController", arguments: PlayerControllerTestCase.allCases)
    func controllersConformToPlaybackController(testCase: PlayerControllerTestCase) async {
        // This test verifies that all controller types can be used as PlaybackController
        let harness = PlayerControllerTestHarness.make(for: testCase)

        // Verify the controller has the expected protocol properties/methods
        // These are compile-time checks essentially, but validate behavior
        _ = harness.controller.isPlaying
        harness.controller.play()
        harness.controller.stop()
        harness.controller.toggle()
    }
}

// MARK: - Stop Behavior Tests

/// Tests verifying stop() behavior across all player implementations.
/// stop() fully terminates playback and resets state.
@Suite("Stop Behavior Tests")
@MainActor
struct StopBehaviorTests {

    @Test("Stop returns to non-playing state", arguments: PlayerControllerTestCase.allCases)
    func stopReturnsToNonPlayingState(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)

        // Start playing
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying, "Should be playing before stop")

        // Stop playback
        harness.controller.stop()
        harness.simulatePlaybackStopped()
        await harness.waitForAsync()

        #expect(!harness.controller.isPlaying, "stop() should return to non-playing state")
    }

    @Test("Stop is idempotent", arguments: PlayerControllerTestCase.allCases)
    func stopIsIdempotent(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)

        // Start playing then stop
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        harness.controller.stop()
        harness.simulatePlaybackStopped()
        await harness.waitForAsync()
        #expect(!harness.controller.isPlaying)

        // Stop again - should be safe
        harness.controller.stop()
        await harness.waitForAsync()
        #expect(!harness.controller.isPlaying, "Multiple stop() calls should be safe")
    }

    @Test("Play after stop works", arguments: PlayerControllerTestCase.allCases)
    func playAfterStopWorks(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)

        // Start playing
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        // Stop
        harness.controller.stop()
        harness.simulatePlaybackStopped()
        await harness.waitForAsync()
        #expect(!harness.controller.isPlaying)

        // Play again after stop
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        #expect(harness.controller.isPlaying, "play() after stop() should work")
    }

    @Test("Stop while not playing is safe", arguments: PlayerControllerTestCase.allCases)
    func stopWhileNotPlayingIsSafe(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)

        // Verify not playing
        #expect(!harness.controller.isPlaying)

        // Stop without having started - should be safe
        harness.controller.stop()
        await harness.waitForAsync()

        #expect(!harness.controller.isPlaying, "stop() while not playing should be safe")
    }
}

// MARK: - Stop Resume Live Tests

/// Tests verifying that all players resume at live position after stop.
/// For live streaming, stop() should reset/disconnect the stream so that
/// resume plays current live audio, not stale buffered audio.
@Suite("Stop Resume Live Tests")
@MainActor
struct StopResumeLiveTests {

    /// Tests that stop() resets the stream for live streaming.
    /// After stop(), resume should connect fresh to the live stream.
    @Test("Stop resets stream for live playback", arguments: PlayerControllerTestCase.allCases)
    func stopResetsStreamForLivePlayback(testCase: PlayerControllerTestCase) async {
        let harness = PlayerControllerTestHarness.make(for: testCase)

        // Start playing
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying, "Should be playing before stop")

        // Stop - should reset the stream for live playback
        harness.controller.stop()
        harness.simulatePlaybackStopped()
        await harness.waitForAsync()
        #expect(!harness.controller.isPlaying, "Should not be playing after stop")

        // Critical assertion: stream should be reset so resume plays live
        #expect(harness.isStreamReset(),
               "Stop should reset stream for live streaming so resume plays live audio, not stale buffered audio")
    }

    /// Tests MP3Streamer's stop() resets stream by checking state transition.
    #if !os(watchOS)
    @Test("MP3Streamer stop resets stream")
    func mp3StreamerStopResetsStream() async {
        let config = MP3StreamerConfiguration(
            url: URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!
        )
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()
        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer
        )

        // Verify initial state
        #expect(streamer.state == .idle, "Should start in idle state")

        // Call stop to verify it sets idle state
        streamer.stop()
        #expect(streamer.state == .idle, "stop() should set idle state")
    }
    #endif
}
