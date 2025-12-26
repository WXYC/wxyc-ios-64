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

    @Test("Streamer initialization", .tags(.initialization))
    func testStreamerInitialization() {
        let config = AVAudioStreamerConfiguration(url: Self.testStreamURL)
        let streamer = AVAudioStreamer(configuration: config)

        #expect(streamer.state == .idle)
        #expect(streamer.volume == 1.0)
    }

    @Test("Volume control")
    func testVolumeControl() {
        let config = AVAudioStreamerConfiguration(url: Self.testStreamURL)
        let streamer = AVAudioStreamer(configuration: config)

        #expect(streamer.volume == 1.0)
        streamer.volume = 0.5
        #expect(streamer.volume == 0.5)
        streamer.volume = 0.0
        #expect(streamer.volume == 0.0)
        streamer.volume = 1.0
        #expect(streamer.volume == 1.0)
    }

    // MARK: - Integration Tests (require network)

    @Test("Connect to live stream", .tags(.integration, .network))
    func testConnectToLiveStream() async throws {
        let config = AVAudioStreamerConfiguration(url: Self.testStreamURL)
        let streamer = AVAudioStreamer(configuration: config)
        let delegate = StreamDelegate()
        streamer.delegate = delegate

        try await streamer.play()

        // Wait for any state change
        let state = try await delegate.stateStream.first(timeout: 4)
        #expect(state != .idle, "Stream should transition from idle state")

        streamer.stop()
        #expect(streamer.state == .idle)
    }

    @Test("Receive PCM buffers from live stream", .tags(.integration, .network))
    func testReceivePCMBuffers() async throws {
        let config = AVAudioStreamerConfiguration(url: Self.testStreamURL)
        let streamer = AVAudioStreamer(configuration: config)
        let delegate = StreamDelegate()
        streamer.delegate = delegate

        try await streamer.play()

        let buffer = try await delegate.bufferStream.first(timeout: 4)
        #expect(buffer.format.channelCount > 0)
        #expect(buffer.frameLength > 0)

        streamer.stop()
    }

    @Test("State transitions to playing", .tags(.integration, .network))
    func testStateTransitions() async throws {
        let config = AVAudioStreamerConfiguration(url: Self.testStreamURL)
        let streamer = AVAudioStreamer(configuration: config)
        let delegate = StreamDelegate()
        streamer.delegate = delegate

        #expect(streamer.state == .idle)

        try await streamer.play()

        let state = try await delegate.stateStream.first(timeout: 4) { $0 == .playing }
        #expect(state == .playing)

        streamer.stop()
        #expect(streamer.state == .idle)
    }

    @Test("Pause and resume", .tags(.integration, .network))
    func testPauseAndResume() async throws {
        let config = AVAudioStreamerConfiguration(url: Self.testStreamURL)
        let streamer = AVAudioStreamer(configuration: config)
        let delegate = StreamDelegate()
        streamer.delegate = delegate

        try await streamer.play()

        _ = try await delegate.stateStream.first(timeout: 2) { $0 == .playing }

        streamer.pause()
        #expect(streamer.state == .paused)

        try await streamer.play()

        let state = try await delegate.stateStream.first(timeout: 2) { $0 == .playing }
        #expect(state == .playing)

        streamer.stop()
    }
}

// MARK: - Stream-based Test Delegate

/// A delegate that exposes callbacks as AsyncStreams for easy testing.
@MainActor
final class StreamDelegate: @preconcurrency AVAudioStreamerDelegate {
    private let stateContinuation: AsyncStream<StreamingAudioState>.Continuation
    private let bufferContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation

    let stateStream: AsyncStream<StreamingAudioState>
    let bufferStream: AsyncStream<AVAudioPCMBuffer>

    init() {
        var stateCont: AsyncStream<StreamingAudioState>.Continuation!
        stateStream = AsyncStream { stateCont = $0 }
        stateContinuation = stateCont

        var bufferCont: AsyncStream<AVAudioPCMBuffer>.Continuation!
        bufferStream = AsyncStream { bufferCont = $0 }
        bufferContinuation = bufferCont
    }

    deinit {
        stateContinuation.finish()
        bufferContinuation.finish()
    }

    nonisolated func audioStreamer(didOutput buffer: AVAudioPCMBuffer, at time: AVAudioTime?) {
        bufferContinuation.yield(buffer)
    }

    nonisolated func audioStreamer(didChangeState state: StreamingAudioState) {
        stateContinuation.yield(state)
    }

    nonisolated func audioStreamer(didEncounterError error: Error) {
        stateContinuation.finish()
        bufferContinuation.finish()
    }
}

// MARK: - AsyncStream Extensions

extension AsyncStream where Element: Sendable {
    /// Returns the first element, or throws TimeoutError if timeout is reached.
    func first(timeout: TimeInterval) async throws -> Element {
        try await first(timeout: timeout) { _ in true }
    }

    /// Returns the first element matching the predicate, or throws TimeoutError.
    func first(timeout: TimeInterval, where predicate: @escaping @Sendable (Element) -> Bool) async throws -> Element {
        try await withThrowingTaskGroup(of: Element.self) { group in
            group.addTask {
                for await element in self {
                    if predicate(element) {
                        return element
                    }
                }
                throw CancellationError()
            }

            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw TimeoutError()
            }

            guard let result = try await group.next() else {
                throw TimeoutError()
            }
            group.cancelAll()
            return result
        }
    }
}

struct TimeoutError: Error, CustomStringConvertible {
    var description: String { "Operation timed out" }
}

// MARK: - Test Tags

extension Tag {
    @Tag static var initialization: Self
    @Tag static var integration: Self
    @Tag static var network: Self
}

#endif // !os(watchOS)
