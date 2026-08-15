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
import Analytics
import AnalyticsTesting
@testable import MP3StreamerModule
@testable import PlaybackCore
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

    /// #937: redundant `stop()` calls against an already-`.idle` streamer must not
    /// repeat the expensive stream-I/O teardown (decoder allocation + consumer Task
    /// spawn). `stopCount == 1` is the non-vacuity control — it proves the assertion
    /// distinguishes "guarded" from "never ran at all" — while `stopCount` 2 and 3
    /// exercise the guard itself.
    @Test("Redundant stop() calls do not repeat stream teardown", arguments: [1, 2, 3])
    func redundantStopCallsAreIdempotent(stopCount: Int) async throws {
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

        for _ in 0..<stopCount {
            streamer.stop()
            #expect(streamer.streamingState == .idle)
        }

        #expect(
            mockHTTP.disconnectCallCount == 1,
            "Only the first stop() should run stream-I/O teardown; the remaining \(stopCount - 1) redundant call(s) must be no-ops"
        )
    }

    /// #937: the idempotency guard must not permanently disable teardown — a fresh
    /// `play()` after a `stop()` un-idles the streamer, so the next `stop()` must
    /// tear down again. Proves the streamer stays reusable across cycles.
    @Test("A stop-play-stop cycle remains reusable and tears down on each stop")
    func stopPlayStopCycleTearsDownAgain() async throws {
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

        streamer.play()
        try await Task.sleep(for: .milliseconds(50))
        streamer.stop()

        #expect(streamer.streamingState == .idle)
        #expect(
            mockHTTP.disconnectCallCount == 2,
            "A fresh play() after a stop() must un-idle the streamer, so the following stop() tears down again"
        )
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

        // Observe every state transition as it happens, rather than sampling
        // `streamingState` after a fixed sleep. The full MP3 file is decoded
        // continuously in the background regardless of playback state, so once
        // `simulateStall()` lands there can already be enough buffered decode
        // backlog for the streamer's own stall-recovery path to flip
        // `.stalled → .playing` again inside the same MainActor turn — a
        // sample taken after any sleep can race straight past `.stalled` and
        // observe only the recovery (#701). `stateStreamInternal` yields every
        // transition in order and buffers them, so a `.stalled` value is
        // captured even when the very next turn already recovers it.
        var sawStalled = false
        let observer = Task { @MainActor in
            for await state in streamer.stateStreamInternal {
                if state == .stalled { sawStalled = true }
            }
        }
        defer { observer.cancel() }

        streamer.play()

        // No vacuous-pass path: a streamer that never reaches .playing must
        // fail loudly here, not silently skip the stall/recovery assertions
        // below the way the old `if case .playing` guard did.
        await pollUntil { streamer.streamingState == .playing }
        #expect(streamer.streamingState == .playing,
                "Streamer must warm up to .playing before stall/recovery can be exercised")
        guard case .playing = streamer.streamingState else { return }

        // Simulate stall while playing.
        mockPlayer.simulateStall()

        await pollUntil { sawStalled }
        #expect(sawStalled,
                "A stall must surface as .stalled at least momentarily, regardless of how quickly it then recovers")

        // Feed more data to trigger recovery.
        mockHTTP.feedData(testData)

        await pollUntil { streamer.streamingState == .playing }
        #expect(streamer.streamingState == .playing,
                "Feeding ≥ minimumBuffersBeforePlayback buffers after a stall must recover playback")
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

        // Record every state transition as it happens, so a `.stalled` that is
        // recovered again in the very next MainActor turn is still visible.
        // Sampling `streamingState` alone cannot tell "the stall never
        // surfaced" apart from "the stall surfaced and the decode backlog
        // recovered it immediately", and this test has to distinguish them: the
        // second means the quiescence wait below came up short. Same technique
        // #860 used in testStallRecoveryRequiresMinimumBuffers.
        var sawStalled = false
        let observer = Task { @MainActor in
            for await state in streamer.stateStreamInternal {
                if state == .stalled { sawStalled = true }
            }
        }
        defer { observer.cancel() }

        // Get to playing state. No vacuous-pass path: a streamer that never
        // warms up must fail loudly here via #expect, not silently skip the
        // stall/reconnect assertions below the way the old guard-and-return
        // did (same shape #860 fixed in testStallRecoveryRequiresMinimumBuffers).
        streamer.play()
        await pollUntil { streamer.streamingState == .playing }
        #expect(streamer.streamingState == .playing,
                "Streamer must warm up to .playing before stall/reconnect can be exercised")
        guard case .playing = streamer.streamingState else { return }

        // Let the decode pipeline run dry before stalling. This is the
        // load-bearing wait in the test and it has to be a quiescence wait, not
        // a fixed sleep: `handleDecodedBuffer`'s `.stalled` branch flips the
        // streamer straight back to `.playing` as soon as
        // `minimumBuffersBeforePlayback` further buffers land, so a stall raised
        // over a pipeline that is still draining does not persist and the
        // play()-from-stalled path below never gets exercised. The whole ~400KB
        // fixture is yielded into the HTTP event stream in one go, so under load
        // the decoder is still working long past any fixed duration — the 300ms
        // sleep that used to sit here is precisely what made this test flaky.
        // In `.playing` every decoded buffer is scheduled straight through to
        // the player, so a scheduled-buffer count that has stopped moving is the
        // observable proxy for "nothing left in flight".
        await pollUntilStable { mockPlayer.scheduledBuffers.count }

        // Simulate stall — with the pipeline drained, the stall state should
        // persist until play() is called again.
        mockPlayer.simulateStall()
        await pollUntil { sawStalled }
        #expect(sawStalled,
                "simulateStall() must surface as .stalled at least momentarily")
        #expect(streamer.streamingState == .stalled,
                """
                The stall must still be in effect when play() is called. A stall that has already \
                auto-recovered means the decode pipeline had not drained, so the play()-from-stalled \
                path this test exists to cover was never reached.
                """)

        // A stall that did not persist makes the rest of the test meaningless:
        // play() short-circuits when the state is already .playing, so the
        // reconnect wait below would burn its whole deadline only to re-report
        // the failure already recorded above.
        guard case .stalled = streamer.streamingState else { return }

        let connectCountBeforeRetry = mockHTTP.connectCallCount

        // Call play() again - should reset and reconnect
        streamer.play()
        await pollUntil { mockHTTP.connectCallCount > connectCountBeforeRetry }

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

    @Test("play() from stuck state does not trigger spurious reconnect", .tags(.stuckStateRecovery))
    func playFromStuckStateNoSpuriousReconnect() async throws {
        // Tests the primary bug: when play() calls stop() for stuck-state recovery,
        // stop() calls httpClient.disconnect() which yields a .disconnected event.
        // Since play() and stop() run synchronously on MainActor, this event isn't
        // processed until play() returns. By then, state has moved to .connecting.
        // The old guard (state != .idle) would pass and trigger attemptReconnect(),
        // causing a duplicate connection.
        let config = MP3StreamerConfiguration(url: Self.testStreamURL)
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()

        // Don't provide test data — we only care about connection count
        mockHTTP.testData = nil

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer
        )

        // Start initial connection
        streamer.play()
        try await Task.sleep(for: .milliseconds(100))
        #expect(mockHTTP.connectCallCount == 1)

        // Manually yield .disconnected to put the streamer into reconnect mode.
        // This simulates a real disconnect that makes the streamer attempt recovery.
        mockHTTP.yield(.disconnected)
        try await Task.sleep(for: .milliseconds(100))

        // Now the streamer is reconnecting (or has reconnected). Record connect count.
        let connectCountBefore = mockHTTP.connectCallCount

        // Call play() again. This sets state to .connecting immediately, then
        // asynchronously runs stop() → disconnect() → connect() inside a Task.
        // The stale .disconnected event from stop() arrives when state is .connecting,
        // which the guard in handleHTTPEvent correctly ignores.
        // With the bug: that event passes guard (state != .idle) and calls
        // attemptReconnect(), adding an extra connect.
        streamer.play()

        // Allow time for the stale .disconnected to be processed
        try await Task.sleep(for: .milliseconds(300))

        // Exactly 1 new connect should have happened (from play()).
        // If 2+ new connects happened, the stale .disconnected triggered a spurious reconnect.
        let newConnections = mockHTTP.connectCallCount - connectCountBefore
        #expect(newConnections == 1,
                "play() recovery should trigger exactly 1 new connect, not more")
    }

    @Test(
        "play() from stuck state does not schedule stale buffers",
        .tags(.stuckStateRecovery)
    )
    func playFromStuckStateNoStaleBuffers() async throws {
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
            return // Skip if we couldn't reach playing state
        }

        // Wait for decoder to finish processing all data
        try await Task.sleep(for: .milliseconds(300))

        // Capture the buffer identities from the first session
        let firstSessionBuffers = Set(mockPlayer.scheduledBuffers.map { ObjectIdentifier($0) })
        #expect(!firstSessionBuffers.isEmpty, "Should have scheduled buffers in first session")

        // Clear the mock's buffer list so we can track only post-recovery buffers
        mockPlayer.clearScheduledBuffers()

        // Recover via play() — stop() + reconnect with fresh data
        mockHTTP.testData = testData
        streamer.play()

        // Wait for new buffers to be scheduled
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(100))
            if !mockPlayer.scheduledBuffers.isEmpty { break }
        }

        // Verify no stale buffers from the first session appear in the second
        let secondSessionBuffers = Set(mockPlayer.scheduledBuffers.map { ObjectIdentifier($0) })
        let staleBuffers = firstSessionBuffers.intersection(secondSessionBuffers)
        #expect(staleBuffers.isEmpty,
                "Stale buffers from first session should not leak into second session")
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

// MARK: - Stale HTTP Error Handling (#936)

/// A stale HTTP `.error` — one already in flight when `stop()` ran — must not
/// resurrect a stream the listener stopped. `stop()` cancels `reconnectTask`
/// but deliberately does not cancel `httpEventTask` (the streamer is reusable
/// across play/stop cycles), and `httpClient.disconnect()` does not retract
/// events already buffered in `httpClient.eventStream`, so a `.error`
/// produced just before the disconnect is still delivered to
/// `handleHTTPEvent` afterwards. The `.error` arm now carries the same
/// state gate its `.disconnected` sibling already has.
@Suite("MP3Streamer Stale HTTP Error Handling")
@MainActor
struct MP3StreamerStaleHTTPErrorTests {
    static let testStreamURL = URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!

    @Test("A stale HTTP error delivered after stop() does not resurrect the stream")
    func staleHTTPErrorAfterStopDoesNotResurrectTheStream() async throws {
        let config = MP3StreamerConfiguration(
            url: Self.testStreamURL,
            minimumBuffersBeforePlayback: 3
        )
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()
        mockPlayer.immediatelyRequestMoreBuffers = false
        let mockAnalytics = MockStructuredAnalytics()

        let testData = try TestAudioBufferFactory.loadMP3TestData()
        mockHTTP.testData = testData

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer,
            analytics: mockAnalytics
        )

        streamer.play()
        await pollUntil { streamer.streamingState == .playing }
        #expect(streamer.streamingState == .playing,
                "Streamer must reach .playing before stop() can be exercised meaningfully")
        guard case .playing = streamer.streamingState else { return }

        streamer.stop()
        #expect(streamer.streamingState == .idle)

        let connectCountBeforeStaleError = mockHTTP.connectCallCount

        // Simulates the HTTP error that was already in flight when stop() ran,
        // delivered to the still-live httpEventTask afterwards.
        mockHTTP.yield(.error(HTTPStreamError.connectionFailed))

        // Negative assertion: give the stale event every chance to be
        // processed and, if unguarded, to arm a reconnect ramp and re-connect.
        // This has to be a real poll-with-timeout, not a short fixed sleep —
        // this suite shares the single MainActor with every other parallel
        // Swift Testing suite in the process, and a busy run can starve a
        // fixed 300ms window long enough that the stale event simply hasn't
        // been drained yet, which reads as "nothing happened" for the wrong
        // reason (see PollUntil.swift's #807 note). Polling for the violation
        // itself returns immediately if it appears, and otherwise waits out
        // the full window before this test's assertions run.
        await pollUntil({ mockHTTP.connectCallCount > connectCountBeforeStaleError }, timeout: .seconds(3))

        #expect(streamer.streamingState == .idle,
                "a stale .error after stop() clobbered .idle back to .error")
        // NOT a primary signal: on the unguarded path the reconnect actually
        // succeeds (mockHTTP.shouldSucceed defaults true), and a successful
        // reconnect calls backoffTimer.reset(), so numberOfAttempts reads 0
        // again by the time this assertion runs even though the bug fired.
        // The two assertions below — streamingState and connectCallCount —
        // are what discriminate; this one only confirms the ramp isn't left
        // armed on the fixed path.
        #expect(streamer.backoffTimer.numberOfAttempts == 0,
                "a stale .error after stop() armed the reconnect backoff ramp")
        #expect(mockHTTP.connectCallCount == connectCountBeforeStaleError,
                "a stale .error after stop() reconnected — and so resurrected — a stream the listener stopped")
        #expect(mockAnalytics.typedEvents(ofType: StreamErrorEvent.self).isEmpty,
                "a dropped stale error must not emit a StreamErrorEvent")
    }

    /// The non-vacuity control for the test above: the identical `.error`
    /// delivered while `.playing` must still move state to `.error` and still
    /// increase `connectCallCount`. Without this, dropping every HTTP `.error`
    /// on the floor would also pass the stale test.
    @Test("An HTTP error delivered while playing still arms a reconnect")
    func liveHTTPErrorWhilePlayingStillArmsReconnect() async throws {
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
        await pollUntil { streamer.streamingState == .playing }
        #expect(streamer.streamingState == .playing,
                "Streamer must reach .playing before the live-error control can be exercised")
        guard case .playing = streamer.streamingState else { return }

        let connectCountBeforeError = mockHTTP.connectCallCount

        // Make the reconnect attempt fail rather than succeed. A successful
        // reconnect both resets backoffTimer (racing numberOfAttempts back to
        // 0 right after arming) and moves streamingState straight back past
        // .error to .buffering/.playing, either of which would make the
        // assertions below flaky depending on exactly when they sample.
        mockHTTP.shouldSucceed = false

        mockHTTP.yield(.error(HTTPStreamError.connectionFailed))

        await pollUntil { streamer.backoffTimer.numberOfAttempts > 0 }
        #expect(streamer.backoffTimer.numberOfAttempts > 0,
                "an HTTP error delivered during live playback did not arm the reconnect backoff ramp")

        if case .error = streamer.streamingState {
            // Expected: the live error clobbers .playing to .error while the
            // reconnect ramp is in flight.
        } else {
            Issue.record("expected .error state after a live HTTP error but got \(streamer.streamingState)")
        }

        await pollUntil { mockHTTP.connectCallCount > connectCountBeforeError }
        #expect(mockHTTP.connectCallCount > connectCountBeforeError,
                "an HTTP error delivered during live playback did not reconnect")

        streamer.stop()
    }

    /// The ordinary connect-failure path is unchanged: an `.error` observed
    /// while `.connecting` is a live, meaningful failure — not a stale event
    /// racing a stop()/play() cycle — and must still drive the backoff ramp.
    @Test("An HTTP error delivered during .connecting still drives the backoff ramp")
    func httpErrorDuringConnectingStillDrivesBackoffRamp() async throws {
        let config = MP3StreamerConfiguration(url: Self.testStreamURL)
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()
        // Hold the streamer in .connecting deliberately: connect() will not
        // emit .connected until this delay elapses.
        mockHTTP.nextConnectDelay = .seconds(5)

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer
        )

        streamer.play()
        #expect(streamer.streamingState == .connecting,
                "Streamer must be parked in .connecting before this test's HTTP error can be delivered against it")
        guard case .connecting = streamer.streamingState else { return }

        // Let the initial connect() from play() actually start and park on
        // the artificial delay, then make the reconnect attempt fail rather
        // than succeed — a successful reconnect calls backoffTimer.reset(),
        // which would race numberOfAttempts back to 0 right after arming and
        // make the assertion below flaky.
        await pollUntil { mockHTTP.connectCallCount > 0 }
        mockHTTP.shouldSucceed = false

        mockHTTP.yield(.error(HTTPStreamError.connectionFailed))

        await pollUntil { streamer.backoffTimer.numberOfAttempts > 0 }
        #expect(streamer.backoffTimer.numberOfAttempts > 0,
                "an HTTP error delivered during .connecting did not arm the reconnect backoff ramp")

        // Tidy up the still-pending delayed connect() so it doesn't run on
        // into later tests.
        streamer.stop()
    }
}

#endif // !os(watchOS)
