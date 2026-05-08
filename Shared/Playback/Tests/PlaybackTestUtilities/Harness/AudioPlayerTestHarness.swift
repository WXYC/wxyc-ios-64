//
//  AudioPlayerTestHarness.swift
//  Playback
//
//  Shared test infrastructure for parameterized AudioPlayerProtocol tests.
//  Provides a unified harness for testing both MP3Streamer and RadioPlayer.
//
//  Created by Jake Bromberg on 01/11/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import AVFoundation
import Analytics
import AnalyticsTesting
@testable import PlaybackCore
@testable import RadioPlayerModule
#if !os(watchOS)
@testable import MP3StreamerModule
#endif

// MARK: - Test Resources

#if !os(watchOS)
/// Loads test MP3 data from bundle resources
private func loadTestMP3Data() -> Data? {
    // Try to find the test MP3 file in the test bundle
    let bundle = Bundle.module
    guard let url = bundle.url(forResource: "Washing Machine (tweaked)", withExtension: "mp3") else {
        return nil
    }
    return try? Data(contentsOf: url)
}
#endif

// MARK: - Test Case Enumeration

/// Enumeration of audio player implementations to test
public enum AudioPlayerTestCase: String, CaseIterable, CustomTestStringConvertible, Sendable {
    #if !os(watchOS)
    /// MP3Streamer - URLSession + AudioToolbox based player
    case mp3Streamer
    #endif
    /// RadioPlayer - AVPlayer based player
    case radioPlayer

    public var testDescription: String {
        switch self {
        #if !os(watchOS)
        case .mp3Streamer:
            "MP3Streamer"
        #endif
        case .radioPlayer:
            "RadioPlayer"
        }
    }

    /// Whether this player supports audio buffer streaming
    public var supportsAudioBufferStream: Bool {
        switch self {
        #if !os(watchOS)
        case .mp3Streamer:
            true
        #endif
        case .radioPlayer:
            false
        }
    }
}

// MARK: - Unified Test Harness

/// Unified test harness for all AudioPlayerProtocol implementations.
/// Uses a factory method to create harnesses with mocked dependencies.
@MainActor
public final class AudioPlayerTestHarness {
    public let player: any AudioPlayerProtocol
    public let testCase: AudioPlayerTestCase
    public let notificationCenter: NotificationCenter
    public let mockAnalytics: MockStructuredAnalytics

    // RadioPlayer mocks
    private let mockPlayer: MockPlayer?

    #if !os(watchOS)
    // MP3Streamer mocks
    private let mockHTTPClient: MockHTTPStreamClient?
    private let mockAudioEngine: MockAudioEnginePlayer?
    #endif

    // MARK: - Computed Properties

    public var playCallCount: Int {
        switch testCase {
        #if !os(watchOS)
        case .mp3Streamer:
            mockAudioEngine?.playCallCount ?? 0
        #endif
        case .radioPlayer:
            mockPlayer?.playCallCount ?? 0
        }
    }

    public var stopCallCount: Int {
        switch testCase {
        #if !os(watchOS)
        case .mp3Streamer:
            mockAudioEngine?.stopCallCount ?? 0
        #endif
        case .radioPlayer:
            mockPlayer?.pauseCallCount ?? 0
        }
    }

    // MARK: - Private Initializer

    #if !os(watchOS)
    private init(
        player: any AudioPlayerProtocol,
        testCase: AudioPlayerTestCase,
        notificationCenter: NotificationCenter,
        mockPlayer: MockPlayer?,
        mockHTTPClient: MockHTTPStreamClient?,
        mockAudioEngine: MockAudioEnginePlayer?,
        mockAnalytics: MockStructuredAnalytics
    ) {
        self.player = player
        self.testCase = testCase
        self.notificationCenter = notificationCenter
        self.mockPlayer = mockPlayer
        self.mockHTTPClient = mockHTTPClient
        self.mockAudioEngine = mockAudioEngine
        self.mockAnalytics = mockAnalytics
    }
    #else
    private init(
        player: any AudioPlayerProtocol,
        testCase: AudioPlayerTestCase,
        notificationCenter: NotificationCenter,
        mockPlayer: MockPlayer?,
        mockAnalytics: MockStructuredAnalytics
    ) {
        self.player = player
        self.testCase = testCase
        self.notificationCenter = notificationCenter
        self.mockPlayer = mockPlayer
        self.mockAnalytics = mockAnalytics
    }
    #endif

    // MARK: - Factory Method

    /// Creates a test harness for the specified player type
    public static func make(for testCase: AudioPlayerTestCase) -> AudioPlayerTestHarness {
        let notificationCenter = NotificationCenter()
        let mockAnalytics = MockStructuredAnalytics()

        switch testCase {
        #if !os(watchOS)
        case .mp3Streamer:
            let mockHTTPClient = MockHTTPStreamClient()
            let mockAudioEngine = MockAudioEnginePlayer(analytics: mockAnalytics)

            // Load test MP3 data so state transitions happen naturally
            if let testData = loadTestMP3Data() {
                mockHTTPClient.testData = testData
                mockHTTPClient.chunkSize = 8192 // Larger chunks for faster buffering
            }

            // Enable auto buffer requests for natural playback flow
            mockAudioEngine.immediatelyRequestMoreBuffers = true

            let config = MP3StreamerConfiguration(
                url: URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!,
                minimumBuffersBeforePlayback: 2 // Lower threshold for faster test transitions
            )
            let streamer = MP3Streamer(
                configuration: config,
                httpClient: mockHTTPClient,
                audioPlayer: mockAudioEngine,
                analytics: mockAnalytics
            )

            return AudioPlayerTestHarness(
                player: streamer,
                testCase: testCase,
                notificationCenter: notificationCenter,
                mockPlayer: nil,
                mockHTTPClient: mockHTTPClient,
                mockAudioEngine: mockAudioEngine,
                mockAnalytics: mockAnalytics
            )
        #endif

        case .radioPlayer:
            let mockPlayer = MockPlayer(autoSetRateOnPlay: false)
            let radioPlayer = RadioPlayer(
                player: mockPlayer,
                analytics: mockAnalytics,
                notificationCenter: notificationCenter
            )

            #if !os(watchOS)
            return AudioPlayerTestHarness(
                player: radioPlayer,
                testCase: testCase,
                notificationCenter: notificationCenter,
                mockPlayer: mockPlayer,
                mockHTTPClient: nil,
                mockAudioEngine: nil,
                mockAnalytics: mockAnalytics
            )
            #else
            return AudioPlayerTestHarness(
                player: radioPlayer,
                testCase: testCase,
                notificationCenter: notificationCenter,
                mockPlayer: mockPlayer,
                mockAnalytics: mockAnalytics
            )
            #endif
        }
    }

    // MARK: - Simulation Methods

    /// Simulates playback starting successfully.
    /// For RadioPlayer: posts rate change message (synchronous on MainActor).
    /// For MP3Streamer: waits for natural state transition via test MP3 data.
    public func simulatePlaybackStarted() async {
        switch testCase {
        #if !os(watchOS)
        case .mp3Streamer:
            // MP3Streamer transitions naturally when test MP3 data flows through.
            // Wait for the state to reach .playing (longer timeout for CI environments)
            await waitUntil({ self.player.state == .playing }, timeout: .seconds(5))
        #endif

        case .radioPlayer:
            // Post rate change message - synchronous on MainActor via MainActorNotificationMessage
            mockPlayer?.rate = 1.0
            notificationCenter.post(
                PlayerRateDidChangeMessage(rate: 1.0),
                subject: nil as AVPlayer?
            )
        }
    }

    /// Simulates playback stopping
    public func simulatePlaybackStopped() {
        switch testCase {
        #if !os(watchOS)
        case .mp3Streamer:
            // stop() is called explicitly, state transitions to idle immediately
            break
        #endif

        case .radioPlayer:
            mockPlayer?.rate = 0
        }
    }

    /// Simulates a playback stall.
    ///
    /// For MP3Streamer the stall flows: mock engine yields `.stalled` →
    /// `MP3Streamer.handlePlayerEvent` flips `streamingState` to `.stalled` and
    /// re-emits `.stall` on its own `eventStream`. We disable auto-buffer
    /// requests, drain any pending engine events (so a buffered `.needsMoreBuffers`
    /// can't race ahead of `.stalled`), yield the stall, and then deterministically
    /// wait for `state == .stalled`.
    public func simulateStall() async {
        switch testCase {
        #if !os(watchOS)
        case .mp3Streamer:
            // Stop buffer requests first to prevent auto-recovery
            mockAudioEngine?.immediatelyRequestMoreBuffers = false
            // Drain any in-flight audio-engine events (e.g. queued .needsMoreBuffers)
            // so they can't be processed after the stall and trigger recovery.
            for _ in 0..<8 {
                await Task.yield()
            }
            // Yield the stall event
            mockAudioEngine?.simulateStall()
            // Wait for MP3Streamer's internal task to process the event and
            // transition to .stalled.
            await waitUntil({ self.player.state == .stalled }, timeout: .seconds(1))
        #endif

        case .radioPlayer:
            // Post stall message - synchronous on MainActor
            notificationCenter.post(
                PlaybackStalledMessage(),
                subject: nil as AVPlayerItem?
            )
        }
    }

    /// Simulates recovery from a stall.
    ///
    /// For MP3Streamer, the mock engine yields `.recoveredFromStall`, which
    /// `MP3Streamer.handlePlayerEvent` translates into a transition back to
    /// `.playing` (and re-emits `.recovery`). Wait for that state to land.
    public func simulateRecovery() async {
        switch testCase {
        #if !os(watchOS)
        case .mp3Streamer:
            // Yield recovery event to audio engine mock
            mockAudioEngine?.simulateRecovery()
            // Wait for MP3Streamer's internal task to process the event and
            // transition back to .playing.
            await waitUntil({ self.player.state == .playing }, timeout: .seconds(1))
        #endif

        case .radioPlayer:
            // Rate change message indicates recovery - synchronous on MainActor
            mockPlayer?.rate = 1.0
            notificationCenter.post(
                PlayerRateDidChangeMessage(rate: 1.0),
                subject: nil as AVPlayer?
            )
        }
    }

    /// Yields enough times to let any pending MainActor-isolated work drain.
    /// Only needed for MP3Streamer, whose internal event-listener tasks run on
    /// `MainActor` and need a chance to consume buffered events. A short burst
    /// of `Task.yield()` calls drains the cooperative-scheduler queue
    /// deterministically — strictly stronger than a wall-clock sleep.
    public func waitForAsync() async {
        #if !os(watchOS)
        if testCase == .mp3Streamer {
            for _ in 0..<8 {
                await Task.yield()
            }
        }
        #endif
    }

    /// Polls until `condition` is met or `timeout` expires. The inner backoff
    /// is `Task.yield()` rather than a fixed sleep, so on a `MainActor`-isolated
    /// test the loop progresses as fast as the executor can drain pending work.
    public func waitUntil(_ condition: @escaping @MainActor () -> Bool, timeout: Duration = .seconds(1)) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition() {
            if ContinuousClock.now >= deadline {
                return
            }
            await Task.yield()
        }
    }

    /// Awaits a task with timeout, cancelling if timeout expires.
    /// Uses `ContinuousClock.sleep` (not `Task.sleep`) for the timeout deadline
    /// — the wait itself is bounded by `task.value` completing, not by polling.
    public func awaitTask<T: Sendable>(_ task: Task<T, Never>, timeout: Duration) async {
        let timeoutTask = Task {
            try? await ContinuousClock().sleep(for: timeout)
            task.cancel()
        }
        _ = await task.value
        timeoutTask.cancel()
    }
}
