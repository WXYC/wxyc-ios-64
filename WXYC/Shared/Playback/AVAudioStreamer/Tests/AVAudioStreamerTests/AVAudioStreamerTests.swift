import Testing
import Foundation
import AVFoundation
@testable import AVAudioStreamer

@Suite("AVAudioStreamer Tests")
struct AVAudioStreamerTests {
    // Test stream URL
    static let testStreamURL = URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!

    @Test("Configuration initialization")
    func testConfigurationInitialization() {
        let config = StreamingAudioConfiguration(url: Self.testStreamURL)

        #expect(config.url == Self.testStreamURL)
        #expect(config.autoReconnect == true)
        #expect(config.maxReconnectAttempts == 3)
        #expect(config.bufferQueueSize == 20)
        #expect(config.minimumBuffersBeforePlayback == 5)
    }

    @Test("Custom configuration")
    func testCustomConfiguration() {
        let config = StreamingAudioConfiguration(
            url: Self.testStreamURL,
            autoReconnect: false,
            maxReconnectAttempts: 5,
            bufferQueueSize: 30,
            minimumBuffersBeforePlayback: 10
        )

        #expect(config.autoReconnect == false)
        #expect(config.maxReconnectAttempts == 5)
        #expect(config.bufferQueueSize == 30)
        #expect(config.minimumBuffersBeforePlayback == 10)
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
        await MainActor.run {
            let config = StreamingAudioConfiguration(url: Self.testStreamURL)
            let streamer = AVAudioStreamer(configuration: config)

            #expect(streamer.state == .idle)
            #expect(streamer.volume == 1.0)
        }
    }

    @Test("Connect to live stream", .tags(.integration, .network))
    func testConnectToLiveStream() async throws {
        try await MainActor.run {
            let config = StreamingAudioConfiguration(
                url: Self.testStreamURL,
                autoReconnect: false
            )
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
    }

    @Test("Receive PCM buffers from live stream", .tags(.integration, .network))
    func testReceivePCMBuffers() async throws {
        try await MainActor.run {
            let config = StreamingAudioConfiguration(url: Self.testStreamURL)
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
    }

    @Test("State transitions", .tags(.integration, .network))
    func testStateTransitions() async throws {
        try await MainActor.run {
            let config = StreamingAudioConfiguration(url: Self.testStreamURL)
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
    }

    @Test("Pause and resume", .tags(.integration, .network))
    func testPauseAndResume() async throws {
        try await MainActor.run {
            let config = StreamingAudioConfiguration(url: Self.testStreamURL)
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
    }

    @Test("Volume control")
    func testVolumeControl() async {
        await MainActor.run {
            let config = StreamingAudioConfiguration(url: Self.testStreamURL)
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
}

// MARK: - Test Helpers

@MainActor
final class TestDelegate: AVAudioStreamerDelegate {
    var receivedBuffers: [AVAudioPCMBuffer] = []
    var stateChanges: [StreamingAudioState] = []
    var errors: [Error] = []

    func audioStreamer(didOutput buffer: AVAudioPCMBuffer, at time: AVAudioTime?) {
        receivedBuffers.append(buffer)
    }

    func audioStreamer(didChangeState state: StreamingAudioState) {
        stateChanges.append(state)
    }

    func audioStreamer(didEncounterError error: Error) {
        errors.append(error)
    }
}

// MARK: - Test Tags

extension Tag {
    @Tag static var initialization: Self
    @Tag static var integration: Self
    @Tag static var network: Self
}
