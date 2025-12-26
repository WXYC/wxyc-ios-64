import Testing
import Foundation
import AVFoundation
@testable import Playback
import Core

#if !os(watchOS)

@Suite("AVAudioStreamer Tests")
@MainActor
struct AVAudioStreamerTests {
    // Test stream URL
    static let testStreamURL = URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!

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

    @Test("Streamer initialization", .tags(.initialization))
    func testStreamerInitialization() async {
        let config = AVAudioStreamerConfiguration(url: Self.testStreamURL)
        let streamer = AVAudioStreamer(configuration: config)

        #expect(streamer.state == .idle)
        #expect(streamer.volume == 1.0)
    }

    @Test("Connect to live stream", .tags(.integration, .network))
    func testConnectToLiveStream() async throws {
        let config = AVAudioStreamerConfiguration(url: Self.testStreamURL)
        let streamer = AVAudioStreamer(configuration: config)
        let delegate = TestDelegate()
        streamer.delegate = delegate

        // Start streaming
        try await streamer.play()

        // Wait for buffering to start
        try await Task.sleep(for: .seconds(2))

        // Verify state changed from idle
        #expect(streamer.state != .idle)

        // Stop streaming
        streamer.stop()

        // Verify we returned to idle
        #expect(streamer.state == .idle)
    }

    @Test("Receive PCM buffers from live stream", .tags(.integration, .network))
    func testReceivePCMBuffers() async throws {
        let config = AVAudioStreamerConfiguration(url: Self.testStreamURL)
        let streamer = AVAudioStreamer(configuration: config)
        let delegate = TestDelegate()
        streamer.delegate = delegate

        // Start streaming
        try await streamer.play()

        // Wait for buffers to arrive
        try await Task.sleep(for: .seconds(5))

        // Verify we received buffers
        #expect(delegate.receivedBuffers.count > 0)

        // Verify buffer properties
        if let buffer = delegate.receivedBuffers.first {
            #expect(buffer.format.channelCount > 0)
            #expect(buffer.frameLength > 0)
        }

        // Stop streaming
        streamer.stop()
    }

    @Test("State transitions", .tags(.integration, .network))
    func testStateTransitions() async throws {
        let config = AVAudioStreamerConfiguration(url: Self.testStreamURL)
        let streamer = AVAudioStreamer(configuration: config)
        let delegate = TestDelegate()
        streamer.delegate = delegate

        // Initial state should be idle
        #expect(streamer.state == .idle)

        // Start streaming
        try await streamer.play()

        // Should transition through connecting -> buffering -> playing
        try await Task.sleep(for: .seconds(5))

        // Should eventually reach playing state
        if case .playing = streamer.state {
            // Success
        } else if case .buffering = streamer.state {
            // Still buffering, acceptable
        } else {
            Issue.record("Unexpected state: \(streamer.state)")
        }

        // Verify we saw state changes
        #expect(delegate.stateChanges.count > 0)

        // Stop streaming
        streamer.stop()
        #expect(streamer.state == .idle)
    }

    @Test("Pause and resume", .tags(.integration, .network))
    func testPauseAndResume() async throws {
        let config = AVAudioStreamerConfiguration(url: Self.testStreamURL)
        let streamer = AVAudioStreamer(configuration: config)

        // Start streaming
        try await streamer.play()

        // Wait for playback to start
        try await Task.sleep(for: .seconds(5))

        // Pause
        streamer.pause()
        #expect(streamer.state == .paused)

        // Wait a bit
        try await Task.sleep(for: .seconds(1))

        // Resume
        try await streamer.play()

        // Should transition back to playing
        try await Task.sleep(for: .seconds(2))

        if case .playing = streamer.state {
            // Success
        } else {
            Issue.record("Expected playing state after resume, got: \(streamer.state)")
        }

        // Stop streaming
        streamer.stop()
    }

    @Test("Volume control")
    func testVolumeControl() {
        let config = AVAudioStreamerConfiguration(url: Self.testStreamURL)
        let streamer = AVAudioStreamer(configuration: config)

        // Default volume should be 1.0
        #expect(streamer.volume == 1.0)

        // Change volume
        streamer.volume = 0.5
        #expect(streamer.volume == 0.5)

        // Set to minimum
        streamer.volume = 0.0
        #expect(streamer.volume == 0.0)

        // Set to maximum
        streamer.volume = 1.0
        #expect(streamer.volume == 1.0)
    }
}

// MARK: - Test Helpers

@MainActor
final class TestDelegate: @preconcurrency AVAudioStreamerDelegate {
    var receivedBuffers: [AVAudioPCMBuffer] = []
    var stateChanges: [StreamingAudioState] = []
    var errors: [Error] = []

    nonisolated func audioStreamer(didOutput buffer: AVAudioPCMBuffer, at time: AVAudioTime?) {
        Task { @MainActor in
            receivedBuffers.append(buffer)
        }
    }

    nonisolated func audioStreamer(didChangeState state: StreamingAudioState) {
        Task { @MainActor in
            stateChanges.append(state)
        }
    }

    nonisolated func audioStreamer(didEncounterError error: Error) {
        Task { @MainActor in
            errors.append(error)
        }
    }
}

// MARK: - Test Tags

extension Tag {
    @Tag static var initialization: Self
    @Tag static var integration: Self
    @Tag static var network: Self
}

#endif // !os(watchOS)
