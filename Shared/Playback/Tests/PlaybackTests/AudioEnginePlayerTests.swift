import Testing
import Foundation
@preconcurrency import AVFoundation
@testable import Playback

#if !os(watchOS)

@Suite("AudioEnginePlayer Tests")
@MainActor
struct AudioEnginePlayerTests {

    // MARK: - Initialization Tests

    @Test("Initial state is not playing with default volume")
    func testInitialization() {
        let delegate = MockAudioPlayerDelegate()
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format, delegate: delegate)

        #expect(player.isPlaying == false)
        #expect(player.volume == 1.0)
    }

    // MARK: - Volume Control Tests

    @Test("Volume can be set and retrieved")
    func testVolumeControl() {
        let delegate = MockAudioPlayerDelegate()
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format, delegate: delegate)

        #expect(player.volume == 1.0)

        player.volume = 0.5
        #expect(player.volume == 0.5)

        player.volume = 0.0
        #expect(player.volume == 0.0)

        player.volume = 1.0
        #expect(player.volume == 1.0)
    }

    // MARK: - Play Tests

    @Test("Play starts playback and notifies delegate")
    func testPlay() async throws {
        let delegate = MockAudioPlayerDelegate()
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format, delegate: delegate)

        try player.play()

        #expect(player.isPlaying == true)

        // Wait for delegate notification
        let event = try await delegate.eventStream.first(timeout: 2)
        #expect(event == .didStartPlaying)

        player.stop()
    }

    @Test("Play is idempotent - calling twice doesn't double-notify")
    func testPlayIdempotent() async throws {
        let delegate = MockAudioPlayerDelegate()
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format, delegate: delegate)

        try player.play()
        try player.play() // Second call should be no-op

        #expect(player.isPlaying == true)

        // Should only receive one didStartPlaying event
        let event = try await delegate.eventStream.first(timeout: 2)
        #expect(event == .didStartPlaying)

        // Give time for any spurious second event
        try await Task.sleep(for: .milliseconds(100))

        player.stop()
    }

    // MARK: - Pause Tests

    @Test("Pause stops playback and notifies delegate")
    func testPause() async throws {
        let delegate = MockAudioPlayerDelegate()
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format, delegate: delegate)

        try player.play()
        _ = try await delegate.eventStream.first(timeout: 2) // Consume didStartPlaying

        player.pause()

        #expect(player.isPlaying == false)

        let event = try await delegate.eventStream.first(timeout: 2)
        #expect(event == .didPause)

        player.stop()
    }

    @Test("Pause when not playing is a no-op")
    func testPauseWhenNotPlaying() async throws {
        let delegate = MockAudioPlayerDelegate()
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format, delegate: delegate)

        // Should not crash or notify delegate
        player.pause()

        #expect(player.isPlaying == false)

        // Give time for any spurious event
        try await Task.sleep(for: .milliseconds(100))
    }

    // MARK: - Stop Tests

    @Test("Stop stops playback and notifies delegate")
    func testStop() async throws {
        let delegate = MockAudioPlayerDelegate()
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format, delegate: delegate)

        try player.play()
        _ = try await delegate.eventStream.first(timeout: 2) // Consume didStartPlaying

        player.stop()

        #expect(player.isPlaying == false)

        let event = try await delegate.eventStream.first(timeout: 2)
        #expect(event == .didStop)
    }

    @Test("Stop when not running is a no-op")
    func testStopWhenNotRunning() async throws {
        let delegate = MockAudioPlayerDelegate()
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format, delegate: delegate)

        // Should not crash or notify delegate
        player.stop()

        #expect(player.isPlaying == false)

        // Give time for any spurious event
        try await Task.sleep(for: .milliseconds(100))
    }

    // MARK: - Buffer Scheduling Tests

    @Test("Schedule buffer accepts PCM buffer")
    func testScheduleBuffer() async throws {
        let delegate = MockAudioPlayerDelegate()
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format, delegate: delegate)

        try player.play()
        _ = try await delegate.eventStream.first(timeout: 2) // Consume didStartPlaying

        let buffer = TestAudioBufferFactory.makeSilentBuffer()
        player.scheduleBuffer(buffer)

        // Give time for buffer to be scheduled
        try await Task.sleep(for: .milliseconds(100))

        player.stop()
    }

    // MARK: - Stall and Recovery Tests

    @Test("Stall is detected when buffers are exhausted while playing", .tags(.stall))
    func testStallDetection() async throws {
        let delegate = MockAudioPlayerDelegate()
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format, delegate: delegate)

        try player.play()
        _ = try await delegate.eventStream.first(timeout: 2) // Consume didStartPlaying

        // Schedule a very short buffer that will finish quickly
        let shortBuffer = TestAudioBufferFactory.makeSilentBuffer(frameCount: 1024)
        player.scheduleBuffer(shortBuffer)

        // Wait for buffer to finish and stall to be detected
        let event = try await delegate.eventStream.first(timeout: 5) { event in
            event == .didStall
        }
        #expect(event == .didStall)

        player.stop()
    }

    @Test("Recovery from stall when new buffer arrives", .tags(.stall))
    func testRecoveryFromStall() async throws {
        let delegate = MockAudioPlayerDelegate()
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format, delegate: delegate)

        try player.play()
        _ = try await delegate.eventStream.first(timeout: 2) // Consume didStartPlaying

        // Schedule a very short buffer that will finish quickly
        let shortBuffer = TestAudioBufferFactory.makeSilentBuffer(frameCount: 1024)
        player.scheduleBuffer(shortBuffer)

        // Wait for stall
        _ = try await delegate.eventStream.first(timeout: 5) { $0 == .didStall }

        // Schedule a new buffer - should trigger recovery
        let recoveryBuffer = TestAudioBufferFactory.makeSilentBuffer()
        player.scheduleBuffer(recoveryBuffer)

        let event = try await delegate.eventStream.first(timeout: 2) { event in
            event == .didRecoverFromStall
        }
        #expect(event == .didRecoverFromStall)

        player.stop()
    }

    @Test("Requests more buffers when count drops below threshold", .tags(.stall))
    func testRequestMoreBuffers() async throws {
        let delegate = MockAudioPlayerDelegate()
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format, delegate: delegate)

        try player.play()
        _ = try await delegate.eventStream.first(timeout: 2) // Consume didStartPlaying

        // Schedule 3 short buffers - when they start completing,
        // the count will drop below 3 and trigger needsMoreBuffers
        for _ in 0..<3 {
            let buffer = TestAudioBufferFactory.makeSilentBuffer(frameCount: 1024)
            player.scheduleBuffer(buffer)
        }

        // Wait for needsMoreBuffers event
        let event = try await delegate.eventStream.first(timeout: 5) { event in
            event == .needsMoreBuffers
        }
        #expect(event == .needsMoreBuffers)

        player.stop()
    }
}

// MARK: - Test Tags

extension Tag {
    @Tag static var stall: Self
}

#endif // !os(watchOS)
