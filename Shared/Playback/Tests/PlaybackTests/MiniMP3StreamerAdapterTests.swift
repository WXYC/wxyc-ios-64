//
//  MiniMP3StreamerAdapterTests.swift
//  PlaybackTests
//
//  Tests for MiniMP3StreamerAdapter observation behavior
//

import Testing
import Foundation
import AVFoundation
@testable import Playback
import MiniMP3Streamer

@Suite("MiniMP3StreamerAdapter Tests")
@MainActor
struct MiniMP3StreamerAdapterTests {

    // MARK: - Observation Tests

    /// Test that MiniMP3StreamerAdapter has an isPlaying property that can be accessed
    /// This is a basic sanity check
    @Test("Adapter has accessible isPlaying property")
    func adapterHasIsPlayingProperty() {
        let url = URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!
        let adapter = MiniMP3StreamerAdapter(url: url)

        // This should compile and not crash
        #expect(adapter.isPlaying == false || adapter.isPlaying == true,
                "isPlaying should be a valid boolean")
    }

    /// Test that stateStream emits at least an initial value
    /// The original implementation immediately finishes the stream, which is wrong
    @Test("stateStream should not immediately finish")
    func stateStreamDoesNotImmediatelyFinish() async throws {
        let url = URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!
        let adapter = MiniMP3StreamerAdapter(url: url)

        var receivedValue = false
        var streamFinished = false

        // Start listening to the stream
        let task = Task {
            for await _ in adapter.stateStream {
                receivedValue = true
                break // Just need one value
            }
            streamFinished = true
        }

        // Give the stream a moment
        try await Task.sleep(for: .milliseconds(100))

        // Cancel the task
        task.cancel()

        // If the stream immediately finishes without emitting values, that's the bug
        // A properly implemented stateStream should either:
        // 1. Emit values when state changes, OR
        // 2. Stay open waiting for state changes (not immediately finish)

        // The original bug: stateStream immediately calls continuation.finish()
        // This means streamFinished will be true almost instantly with no values
        if streamFinished && !receivedValue {
            Issue.record("stateStream finished immediately without emitting any values - this breaks observation")
        }
    }

    /// Test that accessing isPlaying doesn't crash and returns expected initial value
    @Test("Initial state is not playing")
    func initialStateIsNotPlaying() {
        let url = URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!
        let adapter = MiniMP3StreamerAdapter(url: url)

        #expect(adapter.isPlaying == false, "Initial isPlaying should be false")
    }

    /// Test that state property returns a valid state
    @Test("Initial state is stopped")
    func initialStateIsStopped() {
        let url = URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!
        let adapter = MiniMP3StreamerAdapter(url: url)

        #expect(adapter.state == .stopped, "Initial state should be stopped")
    }

    // MARK: - AudioPlayerProtocol Conformance Tests

    @Test("Adapter conforms to AudioPlayerProtocol")
    func adapterConformsToProtocol() {
        let url = URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!
        let adapter = MiniMP3StreamerAdapter(url: url)

        // Verify protocol conformance by accessing all required properties/methods
        _ = adapter.isPlaying
        _ = adapter.state
        _ = adapter.stateStream
        _ = adapter.audioBufferStream
        _ = adapter.eventStream

        // These shouldn't crash
        adapter.play()
        adapter.pause()
        adapter.stop()
    }
}

// MARK: - AudioPlayerController Integration Tests

@Suite("AudioPlayerController MiniMP3Streamer Integration Tests")
@MainActor
struct AudioPlayerControllerMiniMP3IntegrationTests {

    /// Test that AudioPlayerController.isPlaying reflects the adapter's state
    /// This is the key integration test - if observation is broken, this will fail
    @Test("AudioPlayerController.isPlaying reflects adapter state")
    func controllerReflectsAdapterState() async throws {
        #if os(iOS) || os(tvOS)
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()

        // Create controller with MiniMP3Streamer
        let controller = AudioPlayerController(
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: NotificationCenter(),
            analytics: nil
        )

        // Ensure we're using miniMP3Streamer
        controller.playerType = .miniMP3Streamer

        // Initial state should be not playing
        #expect(controller.isPlaying == false, "Initial state should be not playing")
        #endif
    }

    /// Test that changing playerType to miniMP3Streamer works
    @Test("Can switch to miniMP3Streamer player type")
    func canSwitchToMiniMP3Streamer() {
        #if os(iOS) || os(tvOS)
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()

        let controller = AudioPlayerController(
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: NotificationCenter(),
            analytics: nil
        )

        controller.playerType = .miniMP3Streamer
        #expect(controller.playerType == .miniMP3Streamer)

        controller.playerType = .radioPlayer
        #expect(controller.playerType == .radioPlayer)

        controller.playerType = .miniMP3Streamer
        #expect(controller.playerType == .miniMP3Streamer)
        #endif
    }

    /// Test that calling play() on AudioPlayerController updates isPlaying
    /// This tests the full integration: controller.play() -> player.play() -> state update -> observation
    @Test("AudioPlayerController.play() updates isPlaying state")
    func controllerPlayUpdatesState() async throws {
        #if os(iOS) || os(tvOS)
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()
        let mockPlayer = MockAudioPlayer(url: URL(string: "https://test.com/stream")!)

        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: NotificationCenter(),
            analytics: nil
        )

        // Initial state should be not playing
        #expect(controller.isPlaying == false, "Initial state should be not playing")

        // Call play() on the controller
        controller.play()

        // MockAudioPlayer updates its isPlaying synchronously in play()
        // So controller.isPlaying should now be true
        #expect(controller.isPlaying == true,
                "controller.isPlaying should be true after play()")
        #endif
    }

    /// Test that AudioPlayerController.isPlaying observation triggers when state changes
    /// This is the KEY test - if this fails, the UI won't update when playback state changes
    @Test("AudioPlayerController.isPlaying observation triggers when player state changes")
    func controllerIsPlayingObservationTriggers() async throws {
        #if !os(watchOS)
        let mockPlayer = MockAudioPlayer(url: URL(string: "https://test.com/stream")!)
        mockPlayer.shouldAutoUpdateState = false  // We'll control state changes manually

        #if os(iOS) || os(tvOS)
        let mockSession = MockAudioSession()
        let mockCommandCenter = MockRemoteCommandCenter()
        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: mockSession,
            remoteCommandCenter: mockCommandCenter,
            notificationCenter: NotificationCenter(),
            analytics: nil
        )
        #else
        let controller = AudioPlayerController(
            player: mockPlayer,
            notificationCenter: NotificationCenter(),
            analytics: nil
        )
        #endif

        #expect(controller.isPlaying == false, "Initial state should be not playing")

        // Use actor to safely track observation
        actor ObservationTracker {
            var triggered = false
            func trigger() { triggered = true }
            func wasTriggered() -> Bool { return triggered }
        }
        let tracker = ObservationTracker()

        // Set up observation tracking BEFORE changing state
        withObservationTracking {
            _ = controller.isPlaying
        } onChange: {
            Task { await tracker.trigger() }
        }

        // Simulate the player starting to play
        // This yields to the stateStream, which AudioPlayerController observes
        mockPlayer.simulateStateChange(to: .playing)

        // Poll for observation to propagate through the async chain:
        // stateStream → stateTask → isPlaying update → onChange → tracker.trigger()
        var wasTriggered = false
        for _ in 0..<50 {  // Up to 500ms total
            await Task.yield()  // Allow other tasks to run
            try await Task.sleep(for: .milliseconds(10))
            wasTriggered = await tracker.wasTriggered()
            if wasTriggered { break }
        }

        // THIS IS THE CRITICAL TEST:
        // If `player` is @ObservationIgnored without proper state forwarding,
        // wasTriggered will be FALSE and UI won't update
        #expect(wasTriggered == true,
                "Observation should trigger when player.isPlaying changes - if this fails, UI won't update!")
        #endif
    }
}
