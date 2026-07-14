//
//  StreamErrorAnalyticsTests.swift
//  Playback
//
//  Parameterized tests for stream error analytics reporting.
//  Ensures consistent error reporting across all PlaybackController implementations.
//
//  Created by Claude on 01/17/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
import PlaybackTestUtilities
import AVFoundation
import Core
@testable import Playback
@testable import PlaybackCore
@testable import RadioPlayerModule
#if !os(watchOS)
@testable import MP3StreamerModule
#endif

// MARK: - Stream Error Analytics Tests

/// Tests verifying that stream errors are properly captured to analytics.
/// These tests ensure consistent error reporting across all controller implementations.
@Suite(
    "Stream Error Analytics Tests",
    .disabled(if: ProcessInfo.processInfo.environment["WXYC_SKIP_KNOWN_FLAKES"] == "1", "Known flaky on CI — tracked in #371")
)
@MainActor
struct StreamErrorAnalyticsTests {

    // MARK: - Backoff Exhaustion Tests

    @Test("Backoff exhaustion reports stream error event", arguments: PlayerControllerTestCase.allCases)
    func backoffExhaustionReportsStreamError(testCase: PlayerControllerTestCase) async {
        // Create harness with a backoff timer that exhausts after 1 attempt
        let quickBackoff = ExponentialBackoff(initialWaitTime: 0.01, maximumWaitTime: 0.01, maximumAttempts: 1)
        let harness = PlayerControllerTestHarness.make(for: testCase, backoffTimer: quickBackoff)

        // Start playing
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        // Wait for playback to fully initialize
        try? await Task.sleep(for: .milliseconds(50))

        // Simulate stall to trigger backoff
        harness.simulateStall()

        // Wait for backoff to exhaust (needs time for async processing)
        await harness.waitUntil({ !harness.streamErrorEvents.isEmpty }, timeout: .seconds(2))

        // Verify stream error was captured
        let streamErrors = harness.streamErrorEvents
        #expect(streamErrors.count >= 1, "Should capture at least one stream error event")

        if let error = streamErrors.first {
            #expect(error.errorType == .backoffExhausted, "Error type should be backoffExhausted")
            #expect(error.recoveryMethod == .retryWithBackoff, "Recovery method should be retryWithBackoff")
        }
    }

    @Test("Stream error includes correct player type", arguments: PlayerControllerTestCase.allCases)
    func streamErrorIncludesCorrectPlayerType(testCase: PlayerControllerTestCase) async {
        let quickBackoff = ExponentialBackoff(initialWaitTime: 0.01, maximumWaitTime: 0.01, maximumAttempts: 1)
        let harness = PlayerControllerTestHarness.make(for: testCase, backoffTimer: quickBackoff)

        // Start playing
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        // Wait for playback to fully initialize
        try? await Task.sleep(for: .milliseconds(50))

        // Trigger backoff exhaustion
        harness.simulateStall()
        await harness.waitUntil({ !harness.streamErrorEvents.isEmpty }, timeout: .seconds(2))

        // Verify player type matches test case
        let streamErrors = harness.streamErrorEvents
        #expect(streamErrors.count >= 1, "Should capture stream error event")

        if let error = streamErrors.first {
            let expectedType: PlayerControllerType
            switch testCase {
            #if os(iOS) || os(tvOS)
            case .audioPlayerController:
                expectedType = .mp3Streamer
            #endif
            case .radioPlayerController:
                expectedType = .radioPlayer
            }
            #expect(error.playerType == expectedType, "Player type should match the controller type")
        }
    }

    @Test("Stream error includes session duration", arguments: PlayerControllerTestCase.allCases)
    func streamErrorIncludesSessionDuration(testCase: PlayerControllerTestCase) async {
        let quickBackoff = ExponentialBackoff(initialWaitTime: 0.01, maximumWaitTime: 0.01, maximumAttempts: 1)
        let harness = PlayerControllerTestHarness.make(for: testCase, backoffTimer: quickBackoff)

        // Start playing
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        // Wait a bit to accumulate session duration
        try? await Task.sleep(for: .milliseconds(50))

        // Trigger backoff exhaustion
        harness.simulateStall()
        await harness.waitUntil({ !harness.streamErrorEvents.isEmpty }, timeout: .seconds(2))

        // Verify session duration is present
        let streamErrors = harness.streamErrorEvents
        #expect(streamErrors.count >= 1, "Should capture stream error event")

        if let error = streamErrors.first {
            #expect(error.sessionDuration >= 0, "Session duration should be non-negative")
        }
    }

    @Test("Stream error after stall includes stall duration", arguments: PlayerControllerTestCase.allCases)
    func streamErrorAfterStallIncludesStallDuration(testCase: PlayerControllerTestCase) async {
        let quickBackoff = ExponentialBackoff(initialWaitTime: 0.01, maximumWaitTime: 0.01, maximumAttempts: 1)
        let harness = PlayerControllerTestHarness.make(for: testCase, backoffTimer: quickBackoff)

        // Start playing
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        // Wait for playback to fully initialize
        try? await Task.sleep(for: .milliseconds(50))

        // Trigger stall (which starts the stall timer)
        harness.simulateStall()

        // Wait for backoff to exhaust
        await harness.waitUntil({ !harness.streamErrorEvents.isEmpty }, timeout: .seconds(2))

        // Verify stall duration is present
        let streamErrors = harness.streamErrorEvents
        #expect(streamErrors.count >= 1, "Should capture stream error event")

        if let error = streamErrors.first {
            // Stall duration should be non-nil since error occurred during stall recovery
            #expect(error.stallDuration != nil, "Stall duration should be present for errors during recovery")
            if let stallDuration = error.stallDuration {
                #expect(stallDuration >= 0, "Stall duration should be non-negative")
            }
        }
    }

    @Test("Stream error includes reconnect attempt count", arguments: PlayerControllerTestCase.allCases)
    func streamErrorIncludesReconnectAttemptCount(testCase: PlayerControllerTestCase) async {
        // Use 2 max attempts so we can verify the count
        let quickBackoff = ExponentialBackoff(initialWaitTime: 0.01, maximumWaitTime: 0.01, maximumAttempts: 2)
        let harness = PlayerControllerTestHarness.make(for: testCase, backoffTimer: quickBackoff)

        // Start playing
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        // Wait for playback to fully initialize
        try? await Task.sleep(for: .milliseconds(50))

        // Trigger backoff exhaustion
        harness.simulateStall()
        await harness.waitUntil({ !harness.streamErrorEvents.isEmpty }, timeout: .seconds(2))

        // Verify reconnect attempts count
        let streamErrors = harness.streamErrorEvents
        #expect(streamErrors.count >= 1, "Should capture stream error event")

        if let error = streamErrors.first {
            #expect(error.reconnectAttempts > 0, "Should have recorded reconnect attempts")
        }
    }

    // MARK: - Player Error Event Tests (AudioPlayerController only)

    #if os(iOS) || os(tvOS)
    @Test("Player error event reports stream error analytics")
    func playerErrorEventReportsAnalytics() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        // Start playing
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        // Simulate player error
        harness.simulateError(TestStreamError.networkFailure)
        await harness.waitForAsync()

        // Verify stream error was captured
        let streamErrors = harness.streamErrorEvents
        #expect(streamErrors.count >= 1, "Should capture stream error for player error event")

        if let error = streamErrors.first {
            #expect(error.playerType == .mp3Streamer)
            #expect(error.errorDescription.contains("Network"), "Error description should mention network")
        }
    }

    @Test("Player error with network domain classified as network error")
    func playerErrorWithNetworkDomainClassified() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        // Start playing
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        // Simulate network error
        let networkError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        harness.simulateError(networkError)
        await harness.waitForAsync()

        // Verify error type
        if let error = harness.streamErrorEvents.first {
            #expect(error.errorType == .networkError, "URL errors should be classified as network errors")
        }
    }

    @Test("Player error with AVFoundation domain classified appropriately")
    func playerErrorWithAVFoundationDomainClassified() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        // Start playing
        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        // Simulate AVFoundation error
        let avError = NSError(domain: AVFoundationErrorDomain, code: AVError.unknown.rawValue)
        harness.simulateError(avError)
        await harness.waitForAsync()

        // Verify error type
        if let error = harness.streamErrorEvents.first {
            #expect(error.errorType == .playerError, "AVFoundation errors should be classified as player errors")
        }
    }
    #endif
}

// MARK: - Startup Timeout Classification

/// Deterministic classification test for the startup watchdog escalation
/// (Sentry IOS-31). Kept in its own suite — not gated behind the #371 flake skip
/// that disables `StreamErrorAnalyticsTests` — because the `simulateError` path is
/// synchronous and reliable, so it should run in CI to guard the mapping.
#if os(iOS) || os(tvOS)
@Suite("Startup Timeout Classification")
@MainActor
struct StartupTimeoutClassificationTests {

    @Test("Startup-timeout error classified as startupTimeout")
    func startupTimeoutErrorClassified() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        // Simulate the startup watchdog escalation surfacing through the player's
        // event stream (see MP3Streamer.handleStartupTimeout).
        harness.simulateError(StreamStartupError.timedOut(seconds: 12))
        await harness.waitForAsync()

        // The failure — previously silent — is now visible in analytics with a
        // distinct label.
        let streamErrors = harness.streamErrorEvents
        #expect(streamErrors.count >= 1, "Startup timeout should capture a stream error event")
        if let error = streamErrors.first {
            #expect(error.errorType == .startupTimeout,
                    "StreamStartupError should be classified as startupTimeout")
        }
    }
}
#endif

// MARK: - CoreAudio (avfaudio) Classification

/// Deterministic classification tests for the `com.apple.coreaudio.avfaudio`
/// error domain. Before #514 every avfaudio failure fell through to `.unknown`,
/// hiding real AVAudioEngine / AVAudioSession errors in telemetry. Kept in its
/// own suite (not gated behind the #371 flake skip) because `simulateError` is
/// synchronous and reliable.
#if os(iOS) || os(tvOS)
@Suite("CoreAudio avfaudio Classification")
@MainActor
struct CoreAudioClassificationTests {

    /// The `com.apple.coreaudio.avfaudio` NSError domain string as reported in
    /// the field (see #509 / #514).
    static let avfaudioDomain = "com.apple.coreaudio.avfaudio"

    @Test("CannotInterruptOthers ('!int') classified as sessionActivationConflict")
    func cannotInterruptOthersClassified() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        // FourCC '!int' = 560557684 = AVAudioSessionErrorCodeCannotInterruptOthers.
        let error = NSError(
            domain: Self.avfaudioDomain,
            code: Int(AVAudioSession.ErrorCode.cannotInterruptOthers.rawValue)
        )
        harness.simulateError(error)
        await harness.waitForAsync()

        let streamErrors = harness.streamErrorEvents
        #expect(streamErrors.count >= 1, "avfaudio error should capture a stream error event")
        if let captured = streamErrors.first {
            #expect(captured.errorType == .sessionActivationConflict,
                    "'!int' CannotInterruptOthers should classify as sessionActivationConflict, not unknown")
        }
    }

    @Test("Other avfaudio codes ('what') no longer classified as unknown")
    func otherAvfaudioCodeNotUnknown() async {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()

        // FourCC 'what' = 2003329396, the other observed avfaudio code (#509).
        let error = NSError(domain: Self.avfaudioDomain, code: 2003329396)
        harness.simulateError(error)
        await harness.waitForAsync()

        let streamErrors = harness.streamErrorEvents
        #expect(streamErrors.count >= 1, "avfaudio error should capture a stream error event")
        if let captured = streamErrors.first {
            #expect(captured.errorType != .unknown,
                    "Recognized avfaudio domain errors should no longer fall through to unknown")
            #expect(captured.errorType == .playerError,
                    "Non-interruption avfaudio errors should classify as playerError")
        }
    }
}
#endif
