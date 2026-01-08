import Testing
import Foundation
@preconcurrency import AVFoundation
@testable import AVAudioStreamerModule

#if !os(watchOS)

@Suite("AudioEnginePlayer Tests")
@MainActor
struct AudioEnginePlayerTests {

    // MARK: - Initialization Tests

    @Test("Initial state is not playing with default volume")
    func testInitialization() {
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format)

        #expect(player.isPlaying == false)
        #expect(player.volume == 1.0)
    }

    // MARK: - Volume Control Tests

    @Test("Volume can be set and retrieved")
    func testVolumeControl() {
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format)

        #expect(player.volume == 1.0)

        player.volume = 0.5
        #expect(player.volume == 0.5)

        player.volume = 0.0
        #expect(player.volume == 0.0)

        player.volume = 1.0
        #expect(player.volume == 1.0)
    }

    // MARK: - Play Tests

    @Test("Play starts playback and emits started event")
    func testPlay() async throws {
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format)

        try player.play()

        #expect(player.isPlaying == true)

        // Wait for event
        let event = try await player.eventStream.first(timeout: 2)
        guard case .started = event else {
            Issue.record("Expected .started but got \(event)")
            return
        }

        player.stop()
    }

    @Test("Play is idempotent - calling twice doesn't double-notify")
    func testPlayIdempotent() async throws {
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format)

        try player.play()
        try player.play() // Second call should be no-op

        #expect(player.isPlaying == true)

        // Should only receive one started event
        let event = try await player.eventStream.first(timeout: 2)
        guard case .started = event else {
            Issue.record("Expected .started but got \(event)")
            return
        }

        // Give time for any spurious second event
        try await Task.sleep(for: .milliseconds(100))

        player.stop()
    }

    // MARK: - Pause Tests

    @Test("Pause stops playback and emits paused event")
    func testPause() async throws {
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format)

        try player.play()
        _ = try await player.eventStream.first(timeout: 2) // Consume started

        player.pause()

        #expect(player.isPlaying == false)

        let event = try await player.eventStream.first(timeout: 2)
        guard case .paused = event else {
            Issue.record("Expected .paused but got \(event)")
            return
        }

        player.stop()
    }

    @Test("Pause when not playing is a no-op")
    func testPauseWhenNotPlaying() async throws {
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format)

        // Should not crash or emit event
        player.pause()

        #expect(player.isPlaying == false)

        // Give time for any spurious event
        try await Task.sleep(for: .milliseconds(100))
    }

    // MARK: - Stop Tests

    @Test("Stop stops playback and emits stopped event")
    func testStop() async throws {
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format)

        try player.play()
        _ = try await player.eventStream.first(timeout: 2) // Consume started

        player.stop()

        #expect(player.isPlaying == false)

        let event = try await player.eventStream.first(timeout: 2)
        guard case .stopped = event else {
            Issue.record("Expected .stopped but got \(event)")
            return
        }
    }

    @Test("Stop when not running is a no-op")
    func testStopWhenNotRunning() async throws {
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format)

        // Should not crash or emit event
        player.stop()

        #expect(player.isPlaying == false)

        // Give time for any spurious event
        try await Task.sleep(for: .milliseconds(100))
    }

    // MARK: - Buffer Scheduling Tests

    @Test("Schedule buffer accepts PCM buffer")
    func testScheduleBuffer() async throws {
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format)

        try player.play()
        _ = try await player.eventStream.first(timeout: 2) // Consume started

        let buffer = TestAudioBufferFactory.makeSilentBuffer()
        player.scheduleBuffer(buffer)

        // Give time for buffer to be scheduled
        try await Task.sleep(for: .milliseconds(100))

        player.stop()
    }

    // MARK: - Stall and Recovery Tests

    @Test("Stall is detected when buffers are exhausted while playing", .tags(.stall))
    func testStallDetection() async throws {
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format)

        try player.play()
        _ = try await player.eventStream.first(timeout: 2) // Consume started

        // Schedule a very short buffer that will finish quickly
        let shortBuffer = TestAudioBufferFactory.makeSilentBuffer(frameCount: 1024)
        player.scheduleBuffer(shortBuffer)

        // Wait for buffer to finish and stall to be detected
        let event = try await player.eventStream.first(timeout: 5) { event in
            if case .stalled = event { return true }
            return false
        }
        guard case .stalled = event else {
            Issue.record("Expected .stalled but got \(event)")
            return
        }

        player.stop()
    }

    @Test("Recovery from stall when new buffer arrives", .tags(.stall))
    func testRecoveryFromStall() async throws {
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format)

        try player.play()
        _ = try await player.eventStream.first(timeout: 2) // Consume started

        // Schedule a very short buffer that will finish quickly
        let shortBuffer = TestAudioBufferFactory.makeSilentBuffer(frameCount: 1024)
        player.scheduleBuffer(shortBuffer)

        // Wait for stall
        _ = try await player.eventStream.first(timeout: 5) { event in
            if case .stalled = event { return true }
            return false
        }

        // Schedule a new buffer - should trigger recovery
        let recoveryBuffer = TestAudioBufferFactory.makeSilentBuffer()
        player.scheduleBuffer(recoveryBuffer)

        let event = try await player.eventStream.first(timeout: 2) { event in
            if case .recoveredFromStall = event { return true }
            return false
        }
        guard case .recoveredFromStall = event else {
            Issue.record("Expected .recoveredFromStall but got \(event)")
            return
        }

        player.stop()
    }

    @Test("Requests more buffers when count drops below threshold", .tags(.stall))
    func testRequestMoreBuffers() async throws {
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format)

        try player.play()
        _ = try await player.eventStream.first(timeout: 2) // Consume started

        // Schedule 3 short buffers - when they start completing,
        // the count will drop below 3 and trigger needsMoreBuffers
        for _ in 0..<3 {
            let buffer = TestAudioBufferFactory.makeSilentBuffer(frameCount: 1024)
            player.scheduleBuffer(buffer)
        }

        // Wait for needsMoreBuffers event
        let event = try await player.eventStream.first(timeout: 5) { event in
            if case .needsMoreBuffers = event { return true }
            return false
        }
        guard case .needsMoreBuffers = event else {
            Issue.record("Expected .needsMoreBuffers but got \(event)")
            return
        }

        player.stop()
    }
}

// MARK: - AsyncStream Extension for Testing

extension AsyncStream where Element: Sendable {
    /// Returns the first element matching predicate, or throws TimeoutError if timeout is reached.
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

// MARK: - Test Tags

extension Tag {
    @Tag static var stall: Self
}

#endif // !os(watchOS)
