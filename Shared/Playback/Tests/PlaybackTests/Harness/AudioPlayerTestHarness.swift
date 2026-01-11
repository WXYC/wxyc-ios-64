//
//  AudioPlayerTestHarness.swift
//  PlaybackTests
//
//  Shared test infrastructure for parameterized AudioPlayerProtocol tests.
//  Provides a unified harness for testing both AVAudioStreamer and RadioPlayer.
//

import Testing
import Foundation
import AVFoundation
@testable import PlaybackCore
@testable import RadioPlayerModule
#if !os(watchOS)
@testable import AVAudioStreamerModule
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
enum AudioPlayerTestCase: String, CaseIterable, CustomTestStringConvertible {
    #if !os(watchOS)
    /// AVAudioStreamer - URLSession + AudioToolbox based player
    case avAudioStreamer
    #endif
    /// RadioPlayer - AVPlayer based player
    case radioPlayer

    var testDescription: String {
        switch self {
        #if !os(watchOS)
        case .avAudioStreamer:
            "AVAudioStreamer"
        #endif
        case .radioPlayer:
            "RadioPlayer"
        }
    }

    /// Whether this player supports audio buffer streaming
    var supportsAudioBufferStream: Bool {
        switch self {
        #if !os(watchOS)
        case .avAudioStreamer:
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
final class AudioPlayerTestHarness {
    let player: any AudioPlayerProtocol
    let testCase: AudioPlayerTestCase
    let notificationCenter: NotificationCenter

    // RadioPlayer mocks
    private let mockPlayer: MockPlayerForHarness?

    #if !os(watchOS)
    // AVAudioStreamer mocks
    private let mockHTTPClient: MockHTTPStreamClient?
    private let mockAudioEngine: MockAudioEnginePlayer?
    #endif

    // MARK: - Computed Properties

    var playCallCount: Int {
        switch testCase {
        #if !os(watchOS)
        case .avAudioStreamer:
            mockAudioEngine?.playCallCount ?? 0
        #endif
        case .radioPlayer:
            mockPlayer?.playCallCount ?? 0
        }
    }

    var stopCallCount: Int {
        switch testCase {
        #if !os(watchOS)
        case .avAudioStreamer:
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
        mockPlayer: MockPlayerForHarness?,
        mockHTTPClient: MockHTTPStreamClient?,
        mockAudioEngine: MockAudioEnginePlayer?
    ) {
        self.player = player
        self.testCase = testCase
        self.notificationCenter = notificationCenter
        self.mockPlayer = mockPlayer
        self.mockHTTPClient = mockHTTPClient
        self.mockAudioEngine = mockAudioEngine
    }
    #else
    private init(
        player: any AudioPlayerProtocol,
        testCase: AudioPlayerTestCase,
        notificationCenter: NotificationCenter,
        mockPlayer: MockPlayerForHarness?
    ) {
        self.player = player
        self.testCase = testCase
        self.notificationCenter = notificationCenter
        self.mockPlayer = mockPlayer
    }
    #endif

    // MARK: - Factory Method

    /// Creates a test harness for the specified player type
    static func make(for testCase: AudioPlayerTestCase) -> AudioPlayerTestHarness {
        let notificationCenter = NotificationCenter()

        switch testCase {
        #if !os(watchOS)
        case .avAudioStreamer:
            let mockHTTPClient = MockHTTPStreamClient()
            let mockAudioEngine = MockAudioEnginePlayer()

            // Load test MP3 data so state transitions happen naturally
            if let testData = loadTestMP3Data() {
                mockHTTPClient.testData = testData
                mockHTTPClient.chunkSize = 8192 // Larger chunks for faster buffering
            }

            // Enable auto buffer requests for natural playback flow
            mockAudioEngine.immediatelyRequestMoreBuffers = true

            let config = AVAudioStreamerConfiguration(
                url: URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!,
                minimumBuffersBeforePlayback: 2 // Lower threshold for faster test transitions
            )
            let streamer = AVAudioStreamer(
                configuration: config,
                httpClient: mockHTTPClient,
                audioPlayer: mockAudioEngine
            )

            return AudioPlayerTestHarness(
                player: streamer,
                testCase: testCase,
                notificationCenter: notificationCenter,
                mockPlayer: nil,
                mockHTTPClient: mockHTTPClient,
                mockAudioEngine: mockAudioEngine
            )
        #endif

        case .radioPlayer:
            let mockPlayer = MockPlayerForHarness()
            let radioPlayer = RadioPlayer(
                player: mockPlayer,
                analytics: nil,
                notificationCenter: notificationCenter
            )

            #if !os(watchOS)
            return AudioPlayerTestHarness(
                player: radioPlayer,
                testCase: testCase,
                notificationCenter: notificationCenter,
                mockPlayer: mockPlayer,
                mockHTTPClient: nil,
                mockAudioEngine: nil
            )
            #else
            return AudioPlayerTestHarness(
                player: radioPlayer,
                testCase: testCase,
                notificationCenter: notificationCenter,
                mockPlayer: mockPlayer
            )
            #endif
        }
    }

    // MARK: - Simulation Methods

    /// Simulates playback starting successfully.
    /// For RadioPlayer: posts rate change message (synchronous on MainActor).
    /// For AVAudioStreamer: waits for natural state transition via test MP3 data.
    func simulatePlaybackStarted() async {
        switch testCase {
        #if !os(watchOS)
        case .avAudioStreamer:
            // AVAudioStreamer transitions naturally when test MP3 data flows through.
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
    func simulatePlaybackStopped() {
        switch testCase {
        #if !os(watchOS)
        case .avAudioStreamer:
            // stop() is called explicitly, state transitions to idle immediately
            break
        #endif

        case .radioPlayer:
            mockPlayer?.rate = 0
        }
    }

    /// Simulates a playback stall
    func simulateStall() async {
        switch testCase {
        #if !os(watchOS)
        case .avAudioStreamer:
            // Stop buffer requests first to prevent auto-recovery
            mockAudioEngine?.immediatelyRequestMoreBuffers = false
            // Give any in-flight operations time to complete
            try? await Task.sleep(for: .milliseconds(100))
            // Now yield stall event
            mockAudioEngine?.simulateStall()
            // Give AVAudioStreamer's internal task time to process
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
    func simulateRecovery() async {
        switch testCase {
        #if !os(watchOS)
        case .avAudioStreamer:
            // Yield recovery event to audio engine mock
            mockAudioEngine?.simulateRecovery()
            // Give AVAudioStreamer's internal task time to process and re-yield the event
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

    /// Waits for async operations to complete (only needed for AVAudioStreamer)
    func waitForAsync() async {
        #if !os(watchOS)
        if testCase == .avAudioStreamer {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #endif
    }

    /// Polls until condition is met or timeout expires
    func waitUntil(_ condition: @escaping @MainActor () -> Bool, timeout: Duration = .seconds(1)) async {
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
    func awaitTask<T: Sendable>(_ task: Task<T, Never>, timeout: Duration) async {
        let timeoutTask = Task {
            try? await Task.sleep(for: timeout)
            task.cancel()
        }
        _ = await task.value
        timeoutTask.cancel()
    }
}

// MARK: - Mock Player for RadioPlayer Testing

/// Mock for PlayerProtocol (AVPlayer abstraction) used by RadioPlayer
@MainActor
final class MockPlayerForHarness: PlayerProtocol, @unchecked Sendable {
    nonisolated(unsafe) var rate: Float = 0
    nonisolated(unsafe) var playCallCount = 0
    nonisolated(unsafe) var pauseCallCount = 0
    nonisolated(unsafe) var replaceCurrentItemCallCount = 0

    nonisolated func play() {
        playCallCount += 1
    }

    nonisolated func pause() {
        pauseCallCount += 1
        rate = 0
    }

    nonisolated func replaceCurrentItem(with item: AVPlayerItem?) {
        replaceCurrentItemCallCount += 1
    }

    func reset() {
        rate = 0
        playCallCount = 0
        pauseCallCount = 0
        replaceCurrentItemCallCount = 0
    }
}
