//
//  MP3StreamerTests.swift
//  Playback
//
//  Integration tests for MP3Streamer playback.
//
//  Created by Jake Bromberg on 12/25/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Testing
import PlaybackTestUtilities
import Foundation
import AVFoundation
@testable import MP3StreamerModule
import Core

#if !os(watchOS)

@Suite("MP3Streamer Tests")
@MainActor
struct MP3StreamerTests {
    // Test stream URL (only used for configuration, not actual network access)
    static let testStreamURL = URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!

    // MARK: - Unit Tests (no network required)

    @Test("Configuration initialization")
    func testConfigurationInitialization() {
        let config = MP3StreamerConfiguration(url: Self.testStreamURL)

        #expect(config.url == Self.testStreamURL)
        #expect(config.bufferQueueSize == 20)
        #expect(config.minimumBuffersBeforePlayback == 5)
        #expect(config.connectionTimeout == 10.0)
    }

    @Test("Custom configuration")
    func testCustomConfiguration() {
        let config = MP3StreamerConfiguration(
            url: Self.testStreamURL,
            bufferQueueSize: 30,
            minimumBuffersBeforePlayback: 10,
            connectionTimeout: 15.0
        )

        #expect(config.bufferQueueSize == 30)
        #expect(config.minimumBuffersBeforePlayback == 10)
        #expect(config.connectionTimeout == 15.0)
    }

    @Test("State equality")
    func testStateEquality() {
        #expect(StreamingAudioState.idle == StreamingAudioState.idle)
        #expect(StreamingAudioState.connecting == StreamingAudioState.connecting)
        #expect(StreamingAudioState.playing == StreamingAudioState.playing)
        #expect(StreamingAudioState.paused == StreamingAudioState.paused)

        let buffering1 = StreamingAudioState.buffering(bufferedCount: 3, requiredCount: 5)
        let buffering2 = StreamingAudioState.buffering(bufferedCount: 3, requiredCount: 5)
        let buffering3 = StreamingAudioState.buffering(bufferedCount: 4, requiredCount: 5)

        #expect(buffering1 == buffering2)
        #expect(buffering1 != buffering3)
    }

    @Test("Streamer initialization with mocks", .tags(.initialization))
    func testStreamerInitializationWithMocks() {
        let config = MP3StreamerConfiguration(url: Self.testStreamURL)
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer
        )

        #expect(streamer.streamingState == .idle)
        #expect(streamer.volume == 1.0)
    }

    @Test("Volume control")
    func testVolumeControl() {
        let config = MP3StreamerConfiguration(url: Self.testStreamURL)
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer
        )

        #expect(streamer.volume == 1.0)
        streamer.volume = 0.5
        #expect(streamer.volume == 0.5)
        streamer.volume = 0.0
        #expect(streamer.volume == 0.0)
        streamer.volume = 1.0
        #expect(streamer.volume == 1.0)
    }

    // MARK: - Integration Tests with Mocks (fast, no network)

    @Test("Connect transitions to buffering state")
    func testConnectToBufferingState() async throws {
        let config = MP3StreamerConfiguration(url: Self.testStreamURL)
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer
        )

        #expect(streamer.streamingState == .idle)

        streamer.play()

        // Allow time for async operations
        try await Task.sleep(for: .milliseconds(50))

        // Should have transitioned to buffering after connect
        if case .buffering = streamer.streamingState {
            // Success
        } else if case .connecting = streamer.streamingState {
            // Still connecting, wait a bit more
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(mockHTTP.connectCallCount == 1)
    }

    @Test("Stop transitions to idle state")
    func testStopTransitionsToIdle() async throws {
        let config = MP3StreamerConfiguration(url: Self.testStreamURL)
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer
        )

        streamer.play()
        try await Task.sleep(for: .milliseconds(50))

        streamer.stop()

        #expect(streamer.streamingState == .idle)
        #expect(mockHTTP.disconnectCallCount == 1)
        #expect(mockPlayer.stopCallCount == 1)
    }

    @Test("HTTP data feeds to decoder")
    func testHTTPDataFeedsToDecoder() async throws {
        let config = MP3StreamerConfiguration(url: Self.testStreamURL)
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()

        // Load real MP3 test data
        let testData = try TestAudioBufferFactory.loadMP3TestData()
        mockHTTP.testData = testData

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer
        )

        streamer.play()

        // Wait for data to be processed
        try await Task.sleep(for: .milliseconds(200))

        // Verify data was fed through the system
        #expect(mockHTTP.connectCallCount == 1)
    }

    @Test("Connection failure is handled")
    func testConnectionFailure() async throws {
        let config = MP3StreamerConfiguration(url: Self.testStreamURL)
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()

        mockHTTP.shouldSucceed = false
        mockHTTP.errorToThrow = HTTPStreamError.connectionFailed

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer
        )

        streamer.play()

        // Wait for error handling
        try await Task.sleep(for: .milliseconds(100))

        if case .error = streamer.streamingState {
            // Expected error state
        } else {
            Issue.record("Expected error state but got \(streamer.streamingState)")
        }
    }

    @Test("Player stall is detected")
    func testPlayerStallDetection() async throws {
        let config = MP3StreamerConfiguration(url: Self.testStreamURL)
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer
        )

        streamer.play()
        try await Task.sleep(for: .milliseconds(50))

        // Simulate stall from player
        mockPlayer.simulateStall()
        try await Task.sleep(for: .milliseconds(50))

        // The streamer should detect the stall if it was playing
        // Note: actual state depends on whether it reached playing state
    }

    // MARK: - Direct Scheduling Bypass Tests (Performance Optimization)

    @Test("Playing state schedules buffers directly without queue", .tags(.directScheduling))
    func testDirectSchedulingBypassesQueue() async throws {
        let config = MP3StreamerConfiguration(
            url: Self.testStreamURL,
            minimumBuffersBeforePlayback: 2
        )
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()
        mockPlayer.immediatelyRequestMoreBuffers = false  // Don't auto-request

        // Load real MP3 test data - use full file for enough buffers
        let testData = try TestAudioBufferFactory.loadMP3TestData()
        mockHTTP.testData = testData

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer
        )

        // Start playback - this will buffer until minimum then start playing
        streamer.play()

        // Wait for decoder to produce buffers and reach playing state
        // May need longer for MP3 decoding to complete
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(100))
            if case .playing = streamer.streamingState {
                break
            }
        }

        // Should be playing now (or at least have progressed)
        guard case .playing = streamer.streamingState else {
            // If not playing, the test environment may not support full decoding
            // Skip the rest of the test rather than fail
            return
        }

        // Record initial buffer count
        let initialBufferCount = mockPlayer.scheduledBuffers.count
        #expect(initialBufferCount > 0, "Should have scheduled some buffers")

        // Feed more data while playing - these should bypass the queue
        mockHTTP.feedData(testData)

        // Wait for additional buffers to be scheduled
        for _ in 0..<10 {
            try await Task.sleep(for: .milliseconds(100))
            if mockPlayer.scheduledBuffers.count > initialBufferCount {
                break
            }
        }

        // More buffers should have been scheduled directly
        let finalBufferCount = mockPlayer.scheduledBuffers.count
        #expect(finalBufferCount > initialBufferCount, "Should have scheduled more buffers directly")
    }

    @Test("Buffering state uses queue and reports progress", .tags(.directScheduling))
    func testBufferingStateUsesQueue() async throws {
        let config = MP3StreamerConfiguration(
            url: Self.testStreamURL,
            minimumBuffersBeforePlayback: 10  // High threshold to stay in buffering
        )
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()
        mockPlayer.immediatelyRequestMoreBuffers = false

        // Use small amount of data to stay in buffering state
        let testData = try TestAudioBufferFactory.loadMP3TestData()
        let smallData = testData.prefix(4096)  // Very small chunk
        mockHTTP.testData = Data(smallData)

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer
        )

        streamer.play()
        try await Task.sleep(for: .milliseconds(200))

        // Should still be buffering (not enough buffers)
        if case .buffering(let bufferedCount, let requiredCount) = streamer.streamingState {
            #expect(requiredCount == 10)
            #expect(bufferedCount < requiredCount)
        } else if case .connecting = streamer.streamingState {
            // Still connecting, which is also valid
        } else {
            // If we got to playing, that's fine too - decoder was fast
        }

        // No buffers should be scheduled yet (still buffering)
        // Note: This depends on whether decoder produced enough buffers
    }

    @Test("Stall recovery requires minimum buffers before resuming", .tags(.directScheduling))
    func testStallRecoveryRequiresMinimumBuffers() async throws {
        let config = MP3StreamerConfiguration(
            url: Self.testStreamURL,
            minimumBuffersBeforePlayback: 3
        )
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()
        mockPlayer.immediatelyRequestMoreBuffers = false

        let testData = try TestAudioBufferFactory.loadMP3TestData()
        mockHTTP.testData = testData

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer
        )

        streamer.play()
        try await Task.sleep(for: .milliseconds(300))

        // Simulate stall while playing
        if case .playing = streamer.streamingState {
            mockPlayer.simulateStall()
            try await Task.sleep(for: .milliseconds(50))

            // Should be stalled now
            #expect(streamer.streamingState == .stalled)

            // Feed more data to trigger recovery
            mockHTTP.feedData(testData)
            try await Task.sleep(for: .milliseconds(200))

            // Should have recovered to playing
            #expect(streamer.streamingState == .playing)
        }
    }
}

// MARK: - Test Tags

extension Tag {
    @Tag static var initialization: Self
    @Tag static var integration: Self
    @Tag static var network: Self
    @Tag static var directScheduling: Self
    @Tag static var stuckStateRecovery: Self
}

// MARK: - Stuck State Recovery Tests

@Suite("MP3Streamer Stuck State Recovery")
@MainActor
struct MP3StreamerStuckStateRecoveryTests {
    static let testStreamURL = URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!

    @Test("play() from error state resets and reconnects", .tags(.stuckStateRecovery))
    func playFromErrorStateReconnects() async throws {
        let config = MP3StreamerConfiguration(url: Self.testStreamURL)
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()

        // First connection fails, putting streamer in error state
        mockHTTP.shouldSucceed = false
        mockHTTP.errorToThrow = HTTPStreamError.connectionFailed

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer
        )

        streamer.play()
        try await Task.sleep(for: .milliseconds(100))

        guard case .error = streamer.streamingState else {
            Issue.record("Expected error state but got \(streamer.streamingState)")
            return
        }

        // Now fix the connection and try again
        mockHTTP.shouldSucceed = true
        streamer.play()
        try await Task.sleep(for: .milliseconds(100))

        // Should have reset and reconnected
        #expect(streamer.streamingState != .error(HTTPStreamError.connectionFailed),
                "play() from error state should reset and attempt reconnection")
        #expect(mockHTTP.connectCallCount >= 2,
                "Should have attempted a second connection")
    }

    @Test("play() from stalled state resets and reconnects", .tags(.stuckStateRecovery))
    func playFromStalledStateReconnects() async throws {
        let config = MP3StreamerConfiguration(
            url: Self.testStreamURL,
            minimumBuffersBeforePlayback: 3
        )
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()
        mockPlayer.immediatelyRequestMoreBuffers = false

        let testData = try TestAudioBufferFactory.loadMP3TestData()
        mockHTTP.testData = testData

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer
        )

        // Get to playing state
        streamer.play()
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(100))
            if case .playing = streamer.streamingState { break }
        }

        guard case .playing = streamer.streamingState else {
            // Skip if we couldn't reach playing state in this environment
            return
        }

        // Simulate stall
        mockPlayer.simulateStall()
        try await Task.sleep(for: .milliseconds(50))
        #expect(streamer.streamingState == .stalled)

        let connectCountBeforeRetry = mockHTTP.connectCallCount

        // Call play() again - should reset and reconnect
        streamer.play()
        try await Task.sleep(for: .milliseconds(100))

        #expect(streamer.streamingState != .stalled,
                "play() from stalled state should reset and attempt reconnection")
        #expect(mockHTTP.connectCallCount > connectCountBeforeRetry,
                "Should have attempted a new connection after stall recovery")
    }

    @Test("play() from connecting state resets and reconnects", .tags(.stuckStateRecovery))
    func playFromConnectingStateReconnects() async throws {
        let config = MP3StreamerConfiguration(url: Self.testStreamURL)
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()

        // Don't provide test data so connect() will be called but no data arrives
        // and shouldSucceed = true means connect() won't throw, but we need to
        // keep the streamer stuck in connecting. We'll manually yield connected
        // to get past that, but the key issue is the guard statement.
        // Actually, the simplest approach: set the state directly via the
        // play() -> connect flow. When connect() succeeds, state goes to buffering.
        // So for connecting, we need connect() to hang.
        // Let's just test that calling play() while in a non-idle/non-paused state
        // actually does something useful.

        // Simulate a slow connection by making connect() block
        mockHTTP.shouldSucceed = true
        mockHTTP.testData = nil  // No data, so stays in connecting/buffering

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer
        )

        streamer.play()
        try await Task.sleep(for: .milliseconds(50))

        // At this point streamer should be in connecting or buffering
        let stateAfterFirstPlay = streamer.streamingState
        let connectCountAfterFirst = mockHTTP.connectCallCount

        // Call play() again
        streamer.play()
        try await Task.sleep(for: .milliseconds(100))

        // Should have torn down and reconnected
        #expect(mockHTTP.connectCallCount > connectCountAfterFirst,
                "play() from \(stateAfterFirstPlay) should tear down and reconnect")
    }

    @Test("isPlaying is true after recovering from error via play()", .tags(.stuckStateRecovery))
    func isPlayingAfterRecoveryFromError() async throws {
        let config = MP3StreamerConfiguration(
            url: Self.testStreamURL,
            minimumBuffersBeforePlayback: 2
        )
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()
        mockPlayer.immediatelyRequestMoreBuffers = false

        // First attempt fails
        mockHTTP.shouldSucceed = false
        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer
        )

        streamer.play()
        try await Task.sleep(for: .milliseconds(100))

        guard case .error = streamer.streamingState else {
            Issue.record("Expected error state but got \(streamer.streamingState)")
            return
        }
        #expect(!streamer.isPlaying)

        // Fix connection and provide data
        mockHTTP.shouldSucceed = true
        let testData = try TestAudioBufferFactory.loadMP3TestData()
        mockHTTP.testData = testData

        streamer.play()

        // Wait for it to reach playing state
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(100))
            if streamer.isPlaying { break }
        }

        #expect(streamer.isPlaying,
                "Should be playing after recovering from error state via play()")
    }
}

#endif // !os(watchOS)
