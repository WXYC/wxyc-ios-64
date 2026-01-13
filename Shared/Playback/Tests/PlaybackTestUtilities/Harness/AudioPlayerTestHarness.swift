//
//  AudioPlayerTestHarness.swift
//  PlaybackTestUtilities
//
//  Shared test infrastructure for parameterized AudioPlayerProtocol tests.
//  Provides a unified harness for testing both MP3Streamer and RadioPlayer.
//

import Testing
import Foundation
import AVFoundation
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
    public let mockAnalytics: MockAnalyticsService

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
        mockAnalytics: MockAnalyticsService
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
        mockAnalytics: MockAnalyticsService
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
        let mockAnalytics = MockAnalyticsService()

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
            // Wait for the state to reach .playing
            await waitUntil({ self.player.state == .playing }, timeout: .seconds(2))
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

    /// Simulates a playback stall
    public func simulateStall() async {
        switch testCase {
        #if !os(watchOS)
        case .mp3Streamer:
            // Stop buffer requests first to prevent auto-recovery
            mockAudioEngine?.immediatelyRequestMoreBuffers = false
            // Give any in-flight operations time to complete
            try? await Task.sleep(for: .milliseconds(100))
            // Now yield stall event
            mockAudioEngine?.simulateStall()
            // Give MP3Streamer's internal task time to process
            try? await Task.sleep(for: .milliseconds(100))
        #endif

        case .radioPlayer:
            // Post stall message - synchronous on MainActor
            notificationCenter.post(
                PlaybackStalledMessage(),
                subject: nil as AVPlayerItem?
            )
        }
    }

    /// Simulates recovery from a stall
    public func simulateRecovery() async {
        switch testCase {
        #if !os(watchOS)
        case .mp3Streamer:
            // Yield recovery event to audio engine mock
            mockAudioEngine?.simulateRecovery()
            // Give MP3Streamer's internal task time to process and re-yield the event
            try? await Task.sleep(for: .milliseconds(50))
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

    /// Waits for async operations to complete (only needed for MP3Streamer)
    public func waitForAsync() async {
        #if !os(watchOS)
        if testCase == .mp3Streamer {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #endif
    }

    /// Polls until condition is met or timeout expires
    public func waitUntil(_ condition: @escaping @MainActor () -> Bool, timeout: Duration = .seconds(1)) async {
        let start = Date()
        let timeoutSeconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
        while !condition() {
            if Date().timeIntervalSince(start) > timeoutSeconds {
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Awaits a task with timeout, cancelling if timeout expires
    public func awaitTask<T: Sendable>(_ task: Task<T, Never>, timeout: Duration) async {
        let timeoutTask = Task {
            try? await Task.sleep(for: timeout)
            task.cancel()
        }
        _ = await task.value
        timeoutTask.cancel()
    }
}
