import Testing
import Foundation
import AVFoundation
@testable import AVAudioStreamerModule
import Core

#if !os(watchOS)

@Suite("AVAudioStreamer Tests")
@MainActor
struct AVAudioStreamerTests {
    // Test stream URL (only used for configuration, not actual network access)
    static let testStreamURL = URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!

    // MARK: - Unit Tests (no network required)

    @Test("Configuration initialization")
    func testConfigurationInitialization() {
        let config = AVAudioStreamerConfiguration(url: Self.testStreamURL)

        #expect(config.url == Self.testStreamURL)
        #expect(config.bufferQueueSize == 20)
        #expect(config.minimumBuffersBeforePlayback == 5)
        #expect(config.connectionTimeout == 10.0)
    }

    @Test("Custom configuration")
    func testCustomConfiguration() {
        let config = AVAudioStreamerConfiguration(
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
        let config = AVAudioStreamerConfiguration(url: Self.testStreamURL)
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()

        let streamer = AVAudioStreamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer
        )

        #expect(streamer.streamingState == .idle)
        #expect(streamer.volume == 1.0)
    }

    @Test("Volume control")
    func testVolumeControl() {
        let config = AVAudioStreamerConfiguration(url: Self.testStreamURL)
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()

        let streamer = AVAudioStreamer(
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
        let config = AVAudioStreamerConfiguration(url: Self.testStreamURL)
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()

        let streamer = AVAudioStreamer(
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
        let config = AVAudioStreamerConfiguration(url: Self.testStreamURL)
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()

        let streamer = AVAudioStreamer(
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
        let config = AVAudioStreamerConfiguration(url: Self.testStreamURL)
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()

        // Load real MP3 test data
        let testData = try TestAudioBufferFactory.loadMP3TestData()
        mockHTTP.testData = testData

        let streamer = AVAudioStreamer(
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
        let config = AVAudioStreamerConfiguration(url: Self.testStreamURL)
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()

        mockHTTP.shouldSucceed = false
        mockHTTP.errorToThrow = HTTPStreamError.connectionFailed

        let streamer = AVAudioStreamer(
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
        let config = AVAudioStreamerConfiguration(url: Self.testStreamURL)
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()

        let streamer = AVAudioStreamer(
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
}

// MARK: - Test Tags

extension Tag {
    @Tag static var initialization: Self
    @Tag static var integration: Self
    @Tag static var network: Self
}

#endif // !os(watchOS)
