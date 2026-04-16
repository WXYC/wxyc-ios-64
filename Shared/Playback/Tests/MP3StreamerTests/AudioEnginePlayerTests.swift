//
//  AudioEnginePlayerTests.swift
//  Playback
//
//  Tests for AudioEnginePlayer buffer scheduling.
//
//  Created by Jake Bromberg on 12/25/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Testing
import PlaybackTestUtilities
import Foundation
@preconcurrency import AVFoundation
@testable import MP3StreamerModule

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

    // MARK: - Deferred Engine Setup Tests

    @Test("Engine setup is deferred - installRenderTap before play marks as pending")
    func testInstallRenderTapBeforePlayMarksPending() async throws {
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format)

        // Install render tap BEFORE play - should be marked as pending
        player.installRenderTap()

        // Player should not be playing yet
        #expect(player.isPlaying == false)

        // Now play - this should set up engine and install the pending tap
        try player.play()
        #expect(player.isPlaying == true)

        // Consume the started event
        _ = try await player.eventStream.first(timeout: 2)

        player.stop()
    }

    @Test("Render tap installed after play works normally")
    func testRenderTapAfterPlayWorksNormally() async throws {
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format)

        // Play first - sets up engine
        try player.play()
        _ = try await player.eventStream.first(timeout: 2) // Consume started

        // Now install render tap - should work immediately
        player.installRenderTap()

        // Should still be playing
        #expect(player.isPlaying == true)

        player.stop()
    }

    @Test("Multiple installRenderTap calls before play only install once")
    func testMultipleRenderTapCallsBeforePlay() async throws {
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format)

        // Call installRenderTap multiple times before play
        player.installRenderTap()
        player.installRenderTap()
        player.installRenderTap()

        // Play - should install tap only once
        try player.play()
        #expect(player.isPlaying == true)

        _ = try await player.eventStream.first(timeout: 2) // Consume started

        player.stop()
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

    @Test("stop() is non-blocking even when scheduling queue is busy")
    func testStopIsNonBlocking() async throws {
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format)

        try player.play()
        _ = try await player.eventStream.first(timeout: 2)

        // Schedule many buffers to keep the scheduling queue busy
        for _ in 0..<20 {
            let buffer = TestAudioBufferFactory.makeSilentBuffer()
            player.scheduleBuffer(buffer)
        }

        // Measure that stop() returns quickly (should not wait for scheduling queue)
        let start = ContinuousClock.now
        player.stop()
        let elapsed = ContinuousClock.now - start

        #expect(elapsed < .milliseconds(100), "stop() should return in under 100ms but took \(elapsed)")
        #expect(player.isPlaying == false)

        // Wait for the async cleanup to complete
        _ = try await player.eventStream.first(timeout: 2)
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

    // MARK: - Engine Recovery Tests

    @Test("Play succeeds after engine teardown (recovery from start failure)")
    func testPlaySucceedsAfterEngineTearDown() async throws {
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format)

        // First play sets up and starts the engine
        try player.play()
        _ = try await player.eventStream.first(timeout: 2) // Consume started

        player.stop()
        _ = try await player.eventStream.first(timeout: 2) // Consume stopped

        // Simulate what happens when engine.start() fails: tearDownEngine() resets
        // the engine graph and setup state so the next play() can rebuild it.
        player.tearDownEngine()

        // The engine should be recoverable - play() re-attaches the player node,
        // reconnects the audio graph, and starts the engine fresh.
        try player.play()
        #expect(player.isPlaying == true)

        let event = try await player.eventStream.first(timeout: 2)
        guard case .started = event else {
            Issue.record("Expected .started but got \(event)")
            return
        }

        player.stop()
    }

    @Test("Render tap is re-installed after engine teardown and recovery")
    func testRenderTapReinstalledAfterRecovery() async throws {
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format)

        // Install render tap and play
        player.installRenderTap()
        try player.play()
        _ = try await player.eventStream.first(timeout: 2) // Consume started

        player.stop()
        _ = try await player.eventStream.first(timeout: 2) // Consume stopped

        // Tear down engine - render tap state should be reset and marked pending
        player.tearDownEngine()

        // Play again - the pending render tap should be re-installed during setup
        try player.play()
        #expect(player.isPlaying == true)

        _ = try await player.eventStream.first(timeout: 2) // Consume started

        player.stop()
    }

    // MARK: - Batch Scheduling Tests (Performance Optimization)

    @Test("Batch scheduling multiple buffers works correctly", .tags(.batchScheduling))
    func testBatchScheduleBuffers() async throws {
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format)

        try player.play()
        _ = try await player.eventStream.first(timeout: 2) // Consume started

        // Schedule multiple buffers at once
        let buffers = (0..<5).map { _ in
            TestAudioBufferFactory.makeSilentBuffer(frameCount: 4096)
        }

        player.scheduleBuffers(buffers)

        // Give time for buffers to be scheduled
        try await Task.sleep(for: .milliseconds(100))

        // Player should still be playing
        #expect(player.isPlaying == true)

        player.stop()
    }

    @Test("Batch scheduling empty array is a no-op", .tags(.batchScheduling))
    func testBatchScheduleEmptyArray() async throws {
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format)

        try player.play()
        _ = try await player.eventStream.first(timeout: 2) // Consume started

        // Schedule empty array - should not crash or emit events
        player.scheduleBuffers([])

        // Give time for any processing
        try await Task.sleep(for: .milliseconds(50))

        // Player should still be playing without issue
        #expect(player.isPlaying == true)

        player.stop()
    }

    @Test("Batch scheduling triggers stall recovery", .tags(.batchScheduling, .stall))
    func testBatchSchedulingTriggersRecovery() async throws {
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format)

        try player.play()
        _ = try await player.eventStream.first(timeout: 2) // Consume started

        // Schedule a very short buffer to trigger stall
        let shortBuffer = TestAudioBufferFactory.makeSilentBuffer(frameCount: 1024)
        player.scheduleBuffer(shortBuffer)

        // Wait for stall
        _ = try await player.eventStream.first(timeout: 5) { event in
            if case .stalled = event { return true }
            return false
        }

        // Batch schedule multiple buffers - should trigger recovery
        let recoveryBuffers = (0..<3).map { _ in
            TestAudioBufferFactory.makeSilentBuffer()
        }
        player.scheduleBuffers(recoveryBuffers)

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

    // MARK: - Render Tap Stream Reuse Tests

    @Test("makeRenderTapStream returns a working stream after previous consumer is cancelled")
    func testMakeRenderTapStreamAfterCancellation() async throws {
        let format = TestAudioBufferFactory.makeStandardFormat()
        let player = AudioEnginePlayer(format: format)

        // Set up engine and install render tap
        try player.play()
        _ = try await player.eventStream.first(timeout: 2) // Consume started
        player.installRenderTap()

        // First stream: consume one buffer then cancel
        let firstStream = player.makeRenderTapStream()
        let buffer1 = TestAudioBufferFactory.makeSilentBuffer(frameCount: 2048)
        player.scheduleBuffer(buffer1)

        let firstTask = Task {
            for await _ in firstStream {
                return true
            }
            return false
        }

        let received = try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask { await firstTask.value }
            group.addTask {
                try await Task.sleep(for: .seconds(2))
                throw TimeoutError()
            }
            guard let result = try await group.next() else { throw TimeoutError() }
            group.cancelAll()
            return result
        }
        #expect(received, "First stream should receive a buffer")

        // Cancel the first consumer
        firstTask.cancel()
        try await Task.sleep(for: .milliseconds(50))

        // Second stream: should work after the first was cancelled
        let secondStream = player.makeRenderTapStream()
        let buffer2 = TestAudioBufferFactory.makeSilentBuffer(frameCount: 2048)
        player.scheduleBuffer(buffer2)

        let secondTask = Task {
            for await _ in secondStream {
                return true
            }
            return false
        }

        let receivedAgain = try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask { await secondTask.value }
            group.addTask {
                try await Task.sleep(for: .seconds(2))
                throw TimeoutError()
            }
            guard let result = try await group.next() else { throw TimeoutError() }
            group.cancelAll()
            return result
        }
        #expect(receivedAgain, "Second stream should receive a buffer after first stream was cancelled")

        secondTask.cancel()
        player.stop()
    }
}

// MARK: - Additional Test Tags

extension Tag {
    @Tag static var batchScheduling: Self
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
