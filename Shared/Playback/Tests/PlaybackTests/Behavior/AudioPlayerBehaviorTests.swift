//
//  AudioPlayerBehaviorTests.swift
//  Playback
//
//  Parameterized behavior tests for AudioPlayerProtocol implementations.
//  These tests define the expected behavioral contract that all audio players must follow.
//
//  Created by Jake Bromberg on 01/11/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import PlaybackTestUtilities
import Foundation
import AVFoundation
@testable import PlaybackCore
@testable import RadioPlayerModule
#if !os(watchOS)
@testable import MP3StreamerModule
#endif

// MARK: - Core State Tests

@Suite("AudioPlayer Core State Tests")
@MainActor
struct AudioPlayerCoreStateTests {

    @Test("Initial state is idle", arguments: AudioPlayerTestCase.allCases)
    func initialStateIsIdle(testCase: AudioPlayerTestCase) async {
        let harness = AudioPlayerTestHarness.make(for: testCase)
        #expect(harness.player.state == .idle, "Initial state should be idle")
    }

    @Test("Initial isPlaying is false", arguments: AudioPlayerTestCase.allCases)
    func initialIsPlayingIsFalse(testCase: AudioPlayerTestCase) async {
        let harness = AudioPlayerTestHarness.make(for: testCase)
        #expect(!harness.player.isPlaying, "Initial isPlaying should be false")
    }

    @Test("play() transitions to loading", arguments: AudioPlayerTestCase.allCases)
    func playTransitionsToLoading(testCase: AudioPlayerTestCase) async {
        let harness = AudioPlayerTestHarness.make(for: testCase)
        harness.player.play()

        // Both players should transition from idle. With fast mocks, MP3Streamer
        // may already be in .playing, so accept either loading or playing.
        let validStates: [PlayerState] = [.loading, .playing]
        #expect(validStates.contains(harness.player.state), "play() should transition to loading or playing state")
    }

    @Test("play() eventually transitions to playing", arguments: AudioPlayerTestCase.allCases)
    func playEventuallyTransitionsToPlaying(testCase: AudioPlayerTestCase) async {
        let harness = AudioPlayerTestHarness.make(for: testCase)
        harness.player.play()
        await harness.simulatePlaybackStarted()

        await harness.waitUntil { harness.player.state == .playing }
        #expect(harness.player.state == .playing, "play() should eventually transition to playing")
    }

    @Test("isPlaying is true when playing", arguments: AudioPlayerTestCase.allCases)
    func isPlayingTrueWhenPlaying(testCase: AudioPlayerTestCase) async {
        let harness = AudioPlayerTestHarness.make(for: testCase)
        harness.player.play()
        await harness.simulatePlaybackStarted()
        await harness.waitUntil { harness.player.state == .playing }

        #expect(harness.player.isPlaying, "isPlaying should be true when state is playing")
    }

    @Test("stop() transitions to idle", arguments: AudioPlayerTestCase.allCases)
    func stopTransitionsToIdle(testCase: AudioPlayerTestCase) async {
        let harness = AudioPlayerTestHarness.make(for: testCase)

        // Start playing first
        harness.player.play()
        await harness.simulatePlaybackStarted()
        await harness.waitUntil { harness.player.state == .playing }

        // Stop playback
        harness.player.stop()
        await harness.simulatePlaybackStopped()
        await harness.waitForAsync()

        #expect(harness.player.state == .idle, "stop() should transition to idle state")
    }

    @Test("isPlaying is false after stop", arguments: AudioPlayerTestCase.allCases)
    func isPlayingFalseAfterStop(testCase: AudioPlayerTestCase) async {
        let harness = AudioPlayerTestHarness.make(for: testCase)

        // Start playing first
        harness.player.play()
        await harness.simulatePlaybackStarted()
        await harness.waitUntil { harness.player.state == .playing }

        // Stop playback
        harness.player.stop()
        await harness.simulatePlaybackStopped()
        await harness.waitForAsync()

        #expect(!harness.player.isPlaying, "isPlaying should be false after stop()")
    }
}

// MARK: - Idempotency Tests

@Suite("AudioPlayer Idempotency Tests")
@MainActor
struct AudioPlayerIdempotencyTests {

    @Test("play() while playing is idempotent", arguments: AudioPlayerTestCase.allCases)
    func playWhilePlayingIsIdempotent(testCase: AudioPlayerTestCase) async {
        let harness = AudioPlayerTestHarness.make(for: testCase)

        // Start playing
        harness.player.play()
        await harness.simulatePlaybackStarted()
        await harness.waitUntil { harness.player.state == .playing }
        #expect(harness.player.isPlaying)

        // Play again while playing
        harness.player.play()
        await harness.waitForAsync()

        // Should still be playing
        #expect(harness.player.isPlaying, "Multiple play() calls should keep playing")
    }

    @Test("stop() while idle is idempotent", arguments: AudioPlayerTestCase.allCases)
    func stopWhileIdleIsIdempotent(testCase: AudioPlayerTestCase) async {
        let harness = AudioPlayerTestHarness.make(for: testCase)

        // Verify idle state
        #expect(harness.player.state == .idle)

        // Stop while already idle - should not crash
        harness.player.stop()
        await harness.waitForAsync()

        #expect(harness.player.state == .idle, "stop() while idle should remain idle")
    }

    @Test("Multiple stop() calls are safe", arguments: AudioPlayerTestCase.allCases)
    func multipleStopCallsAreSafe(testCase: AudioPlayerTestCase) async {
        let harness = AudioPlayerTestHarness.make(for: testCase)

        // Start playing first
        harness.player.play()
        await harness.simulatePlaybackStarted()
        await harness.waitUntil { harness.player.state == .playing }

        // Stop multiple times - should not crash
        harness.player.stop()
        await harness.waitForAsync()
        harness.player.stop()
        await harness.waitForAsync()
        harness.player.stop()
        await harness.waitForAsync()

        #expect(harness.player.state == .idle, "Multiple stop() calls should be safe")
    }

    @Test("play() after stop() works", arguments: AudioPlayerTestCase.allCases)
    func playAfterStopWorks(testCase: AudioPlayerTestCase) async {
        let harness = AudioPlayerTestHarness.make(for: testCase)

        // Play
        harness.player.play()
        await harness.simulatePlaybackStarted()
        await harness.waitUntil { harness.player.state == .playing }

        // Stop
        harness.player.stop()
        await harness.simulatePlaybackStopped()
        await harness.waitForAsync()
        #expect(harness.player.state == .idle)

        // Play again
        harness.player.play()
        await harness.simulatePlaybackStarted()
        await harness.waitUntil { harness.player.state == .playing }

        #expect(harness.player.isPlaying, "play() after stop() should work")
    }

    @Test("Rapid play/stop cycles are safe", arguments: AudioPlayerTestCase.allCases)
    func rapidPlayStopCyclesAreSafe(testCase: AudioPlayerTestCase) async {
        let harness = AudioPlayerTestHarness.make(for: testCase)

        for _ in 0..<5 {
            harness.player.play()
            await harness.simulatePlaybackStarted()
            await harness.waitForAsync()

            harness.player.stop()
            await harness.simulatePlaybackStopped()
            await harness.waitForAsync()
        }

        // Should end in idle state
        #expect(harness.player.state == .idle, "Rapid cycles should end in idle")
    }
}

// MARK: - State Stream Tests

@Suite("AudioPlayer State Stream Tests")
@MainActor
struct AudioPlayerStateStreamTests {

    @Test("stateStream yields on play", arguments: AudioPlayerTestCase.allCases)
    func stateStreamYieldsOnPlay(testCase: AudioPlayerTestCase) async throws {
        let harness = AudioPlayerTestHarness.make(for: testCase)

        var receivedStates: [PlayerState] = []
        let iteratorReady = AsyncStream<Void>.makeStream()

        let streamTask = Task {
            var iterator = harness.player.stateStream.makeAsyncIterator()
            iteratorReady.continuation.yield()

            while let state = await iterator.next() {
                receivedStates.append(state)
                if state == .loading || state == .playing {
                    break
                }
            }
        }

        // Wait for iterator to be ready
        for await _ in iteratorReady.stream {
            break
        }
        iteratorReady.continuation.finish()

        // Trigger state change
        harness.player.play()

        // Wait for the stream task to complete (with timeout)
        await harness.awaitTask(streamTask, timeout: .seconds(2))

        #expect(receivedStates.contains(.loading), "stateStream should yield .loading on play()")
    }

    @Test("stateStream yields on stop", arguments: AudioPlayerTestCase.allCases)
    func stateStreamYieldsOnStop(testCase: AudioPlayerTestCase) async throws {
        let harness = AudioPlayerTestHarness.make(for: testCase)

        // Start playing first
        harness.player.play()
        await harness.simulatePlaybackStarted()
        await harness.waitUntil { harness.player.state == .playing }

        var receivedStates: [PlayerState] = []
        let iteratorReady = AsyncStream<Void>.makeStream()

        let streamTask = Task {
            var iterator = harness.player.stateStream.makeAsyncIterator()
            iteratorReady.continuation.yield()

            while let state = await iterator.next() {
                receivedStates.append(state)
                if state == .idle {
                    break
                }
            }
        }

        // Wait for iterator to be ready
        for await _ in iteratorReady.stream {
            break
        }
        iteratorReady.continuation.finish()

        // Trigger stop
        harness.player.stop()
        harness.simulatePlaybackStopped()

        // Wait for the stream task to complete (with timeout)
        await harness.awaitTask(streamTask, timeout: .seconds(2))

        #expect(receivedStates.contains(.idle), "stateStream should yield .idle on stop()")
    }
}

// MARK: - Event Stream Tests

@Suite("AudioPlayer Event Stream Tests")
@MainActor
struct AudioPlayerEventStreamTests {

    @Test("eventStream yields stall event", arguments: AudioPlayerTestCase.allCases)
    func eventStreamYieldsStallEvent(testCase: AudioPlayerTestCase) async throws {
        let harness = AudioPlayerTestHarness.make(for: testCase)

        // Start playing
        harness.player.play()
        await harness.simulatePlaybackStarted()
        await harness.waitUntil { harness.player.state == .playing }

        var receivedStall = false
        let iteratorReady = AsyncStream<Void>.makeStream()

        let streamTask = Task {
            var iterator = harness.player.eventStream.makeAsyncIterator()
            iteratorReady.continuation.yield()

            while let event = await iterator.next() {
                if case .stall = event {
                    receivedStall = true
                    break
                }
            }
        }

        // Wait for iterator to be ready
        for await _ in iteratorReady.stream {
            break
        }
        iteratorReady.continuation.finish()

        // Trigger stall
        await harness.simulateStall()

        // Wait for the stream task to complete (with timeout)
        await harness.awaitTask(streamTask, timeout: .seconds(2))

        #expect(receivedStall, "eventStream should yield .stall event on stall")
    }

    // Note: MP3Streamer has auto-recovery when buffers are available, so it may never
    // enter the stalled state needed for this test. This test focuses on RadioPlayer.
    @Test("eventStream yields recovery event (RadioPlayer)")
    func eventStreamYieldsRecoveryEvent() async throws {
        let harness = AudioPlayerTestHarness.make(for: .radioPlayer)

        // Start playing
        harness.player.play()
        await harness.simulatePlaybackStarted()
        await harness.waitUntil { harness.player.state == .playing }

        // Trigger stall first
        await harness.simulateStall()
        await harness.waitUntil { harness.player.state == .stalled }

        var receivedRecovery = false
        let iteratorReady = AsyncStream<Void>.makeStream()

        let streamTask = Task {
            var iterator = harness.player.eventStream.makeAsyncIterator()
            iteratorReady.continuation.yield()

            while let event = await iterator.next() {
                if case .recovery = event {
                    receivedRecovery = true
                    break
                }
            }
        }

        // Wait for iterator to be ready
        for await _ in iteratorReady.stream {
            break
        }
        iteratorReady.continuation.finish()

        // Trigger recovery
        await harness.simulateRecovery()

        // Wait for the stream task to complete (with timeout)
        await harness.awaitTask(streamTask, timeout: .seconds(2))

        #expect(receivedRecovery, "eventStream should yield .recovery event on recovery")
    }
}

// MARK: - Stall State Tests

@Suite("AudioPlayer Stall State Tests")
@MainActor
struct AudioPlayerStallStateTests {

    // Note: MP3Streamer has auto-recovery when buffers are available, so stall state
    // may be transient. The eventStream stall test verifies the stall event is emitted.
    // This test focuses on RadioPlayer which maintains stable stall state.
    @Test("Stall transitions to stalled state (RadioPlayer)")
    func stallTransitionsToStalledState() async {
        let harness = AudioPlayerTestHarness.make(for: .radioPlayer)

        // Start playing
        harness.player.play()
        await harness.simulatePlaybackStarted()
        await harness.waitUntil { harness.player.state == .playing }

        // Trigger stall
        await harness.simulateStall()

        await harness.waitUntil { harness.player.state == .stalled }
        #expect(harness.player.state == .stalled, "Stall should transition to .stalled state")
    }

    // Note: For MP3Streamer, recovery may happen automatically when buffers are available.
    // This test focuses on RadioPlayer which requires explicit recovery.
    @Test("Recovery transitions back to playing (RadioPlayer)")
    func recoveryTransitionsToPlaying() async {
        let harness = AudioPlayerTestHarness.make(for: .radioPlayer)

        // Start playing
        harness.player.play()
        await harness.simulatePlaybackStarted()
        await harness.waitUntil { harness.player.state == .playing }

        // Trigger stall
        await harness.simulateStall()
        await harness.waitUntil { harness.player.state == .stalled }

        // Trigger recovery
        await harness.simulateRecovery()

        await harness.waitUntil { harness.player.state == .playing }
        #expect(harness.player.state == .playing, "Recovery should transition back to .playing")
    }
}

// MARK: - Render Tap Tests

@Suite("AudioPlayer Render Tap Tests")
@MainActor
struct AudioPlayerRenderTapTests {

    @Test("installRenderTap does not throw", arguments: AudioPlayerTestCase.allCases)
    func installRenderTapDoesNotThrow(testCase: AudioPlayerTestCase) async {
        let harness = AudioPlayerTestHarness.make(for: testCase)

        // Should not crash or throw
        harness.player.installRenderTap()
        await harness.waitForAsync()

        // Clean up
        harness.player.removeRenderTap()
    }

    @Test("removeRenderTap does not throw", arguments: AudioPlayerTestCase.allCases)
    func removeRenderTapDoesNotThrow(testCase: AudioPlayerTestCase) async {
        let harness = AudioPlayerTestHarness.make(for: testCase)

        // Remove without installing first - should not crash
        harness.player.removeRenderTap()
        await harness.waitForAsync()
    }

    @Test("installRenderTap then removeRenderTap is safe", arguments: AudioPlayerTestCase.allCases)
    func installThenRemoveRenderTapIsSafe(testCase: AudioPlayerTestCase) async {
        let harness = AudioPlayerTestHarness.make(for: testCase)

        harness.player.installRenderTap()
        await harness.waitForAsync()

        harness.player.removeRenderTap()
        await harness.waitForAsync()

        // Multiple cycles should be safe
        harness.player.installRenderTap()
        harness.player.removeRenderTap()
        harness.player.installRenderTap()
        harness.player.removeRenderTap()
    }
}

// MARK: - Audio Buffer Stream Tests

@Suite("AudioPlayer Audio Buffer Stream Tests")
@MainActor
struct AudioPlayerAudioBufferStreamTests {

    @Test("audioBufferStream is available", arguments: AudioPlayerTestCase.allCases)
    func audioBufferStreamIsAvailable(testCase: AudioPlayerTestCase) async {
        let harness = AudioPlayerTestHarness.make(for: testCase)

        // Should have an audioBufferStream (even if it's empty for RadioPlayer)
        let stream = harness.player.audioBufferStream
        _ = stream // Just verify it exists
    }

    @Test("RadioPlayer audioBufferStream finishes immediately", arguments: [AudioPlayerTestCase.radioPlayer])
    func radioPlayerAudioBufferStreamFinishesImmediately(testCase: AudioPlayerTestCase) async {
        let harness = AudioPlayerTestHarness.make(for: testCase)

        var bufferCount = 0
        for await _ in harness.player.audioBufferStream {
            bufferCount += 1
        }

        #expect(bufferCount == 0, "RadioPlayer audioBufferStream should finish immediately with no buffers")
    }

    #if !os(watchOS)
    @Test("MP3Streamer supports audio buffer streaming")
    func mp3StreamerSupportsAudioBufferStreaming() async {
        let testCase = AudioPlayerTestCase.mp3Streamer
        #expect(testCase.supportsAudioBufferStream, "MP3Streamer should support audio buffer streaming")
    }
    #endif
}

// MARK: - Protocol Conformance Tests

@Suite("AudioPlayer Protocol Conformance Tests")
@MainActor
struct AudioPlayerProtocolConformanceTests {

    @Test("All players conform to AudioPlayerProtocol", arguments: AudioPlayerTestCase.allCases)
    func allPlayersConformToProtocol(testCase: AudioPlayerTestCase) async {
        let harness = AudioPlayerTestHarness.make(for: testCase)

        // These are compile-time checks but validate the protocol is satisfied
        _ = harness.player.isPlaying
        _ = harness.player.state
        _ = harness.player.stateStream
        _ = harness.player.audioBufferStream
        _ = harness.player.eventStream
        harness.player.play()
        harness.player.stop()
        harness.player.installRenderTap()
        harness.player.removeRenderTap()
    }
}
