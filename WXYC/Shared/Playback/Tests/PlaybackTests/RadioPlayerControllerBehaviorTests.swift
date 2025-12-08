//
//  RadioPlayerControllerBehaviorTests.swift
//  PlaybackTests
//
//  Parameterized tests that verify RadioPlayerController follows the same
//  behavioral contract as AudioPlayerController in PlayerHeaderView.
//
//  These tests mirror PlayerControllerBehaviorTests.swift to ensure consistency.
//

import Testing
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif
import MediaPlayer
@testable import Playback

// MARK: - Mock Player for RadioPlayer

final class MockRadioPlayer: PlayerProtocol, @unchecked Sendable {
    nonisolated(unsafe) var rate: Float = 0
    nonisolated(unsafe) var playCallCount = 0
    nonisolated(unsafe) var pauseCallCount = 0
    nonisolated(unsafe) var replaceCurrentItemCallCount = 0
    
    /// Simulates whether the player is in a "playing" state
    nonisolated(unsafe) var simulatedIsPlaying = false
    
    nonisolated func play() {
        playCallCount += 1
        rate = 1.0
        simulatedIsPlaying = true
    }
    
    nonisolated func pause() {
        pauseCallCount += 1
        rate = 0
        simulatedIsPlaying = false
    }
    
    nonisolated func replaceCurrentItem(with item: AVPlayerItem?) {
        replaceCurrentItemCallCount += 1
    }
    
    func reset() {
        rate = 0
        playCallCount = 0
        pauseCallCount = 0
        replaceCurrentItemCallCount = 0
        simulatedIsPlaying = false
    }
}

// MARK: - Test Harness

/// Test harness for RadioPlayerController tests
@MainActor
final class RadioPlayerControllerTestHarness {
    var mockPlayer: MockRadioPlayer
    var notificationCenter: NotificationCenter
    var testUserDefaults: UserDefaults
    var radioPlayer: RadioPlayer
    var controller: RadioPlayerController
    
    init() {
        mockPlayer = MockRadioPlayer()
        notificationCenter = NotificationCenter()
        testUserDefaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        
        radioPlayer = RadioPlayer(
            streamURL: URL(string: "https://example.com/stream")!,
            player: mockPlayer,
            userDefaults: testUserDefaults,
            analytics: nil,
            notificationCenter: notificationCenter
        )
        
        controller = RadioPlayerController(
            radioPlayer: radioPlayer,
            notificationCenter: notificationCenter,
            remoteCommandCenter: .shared()
        )
    }
    
    /// Simulates the player starting to play by posting rate change notification
    func simulatePlaybackStarted() {
        mockPlayer.rate = 1.0
        mockPlayer.simulatedIsPlaying = true
        notificationCenter.post(name: AVPlayer.rateDidChangeNotification, object: nil)
    }
    
    /// Simulates the player stopping by posting rate change notification
    func simulatePlaybackStopped() {
        mockPlayer.rate = 0
        mockPlayer.simulatedIsPlaying = false
        notificationCenter.post(name: AVPlayer.rateDidChangeNotification, object: nil)
    }
    
    /// Waits for async operations to complete
    func waitForAsync() async {
        // Allow notification handlers to execute
        try? await Task.sleep(for: .milliseconds(100))
    }
}

// MARK: - RadioPlayerController Behavior Tests

@Suite("RadioPlayerController Behavior Tests")
@MainActor
struct RadioPlayerControllerBehaviorTests {
    
    // MARK: - Core Behavior Tests
    
    @Test("play() sets isPlaying to true")
    func playSetsIsPlayingTrue() async throws {
        let harness = RadioPlayerControllerTestHarness()
        
        try harness.controller.play(reason: "test")
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        
        #expect(harness.controller.isPlaying, "play() should set isPlaying to true")
    }
    
    @Test("pause() sets isPlaying to false")
    func pauseSetsIsPlayingFalse() async throws {
        let harness = RadioPlayerControllerTestHarness()
        
        // Start playing
        try harness.controller.play(reason: "test")
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying)
        
        // Pause
        harness.controller.pause()
        harness.simulatePlaybackStopped()
        await harness.waitForAsync()
        
        #expect(!harness.controller.isPlaying, "pause() should set isPlaying to false")
    }
    
    @Test("toggle() while playing pauses")
    func toggleFromPlayingPauses() async throws {
        let harness = RadioPlayerControllerTestHarness()
        
        // Start playing
        try harness.controller.play(reason: "test")
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying)
        
        // Toggle should pause
        try harness.controller.toggle(reason: "test toggle")
        harness.simulatePlaybackStopped()
        await harness.waitForAsync()
        
        #expect(!harness.controller.isPlaying, "toggle() while playing should pause")
    }
    
    @Test("toggle() while paused starts playback")
    func toggleWhilePausedStartsPlayback() async throws {
        let harness = RadioPlayerControllerTestHarness()
        
        // Start paused
        #expect(!harness.controller.isPlaying)
        
        // Toggle should attempt to play
        try harness.controller.toggle(reason: "test toggle")
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        
        #expect(harness.controller.isPlaying, "toggle() while paused should start playback")
    }
    
    @Test("play() calls underlying player")
    func playCallsUnderlyingPlayer() async throws {
        let harness = RadioPlayerControllerTestHarness()
        
        try harness.controller.play(reason: "test")
        await harness.waitForAsync()
        
        #expect(harness.mockPlayer.playCallCount == 1, "play() should call underlying player")
    }
    
    @Test("pause() calls underlying player")
    func pauseCallsUnderlyingPlayer() async throws {
        let harness = RadioPlayerControllerTestHarness()
        
        try harness.controller.play(reason: "test")
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        
        harness.controller.pause()
        
        #expect(harness.mockPlayer.pauseCallCount == 1, "pause() should call underlying player")
    }
}

// MARK: - RadioPlayerController Interruption Handling Tests

#if os(iOS)
@Suite("RadioPlayerController Interruption Handling Tests")
@MainActor
struct RadioPlayerControllerInterruptionTests {
    
    /// Helper to create an interruption notification with the specified type
    private func makeInterruptionNotification(
        type: AVAudioSession.InterruptionType,
        options: AVAudioSession.InterruptionOptions? = nil,
        reason: AVAudioSession.InterruptionReason? = nil
    ) -> Notification {
        var userInfo: [AnyHashable: Any] = [
            AVAudioSessionInterruptionTypeKey: NSNumber(value: type.rawValue)
        ]
        if let options {
            userInfo[AVAudioSessionInterruptionOptionKey] = NSNumber(value: options.rawValue)
        }
        if let reason {
            userInfo[AVAudioSessionInterruptionReasonKey] = NSNumber(value: reason.rawValue)
        }
        return Notification(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: userInfo
        )
    }
    
    @Test("Interruption began with no shouldResume option pauses playback")
    func interruptionBeganPausesPlayback() async throws {
        let harness = RadioPlayerControllerTestHarness()
        
        // Start playing
        try harness.controller.play(reason: "test")
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying)
        
        // Post interruption began notification
        let notification = makeInterruptionNotification(type: .began)
        harness.notificationCenter.post(notification)
        await harness.waitForAsync()
        
        // Should have called pause
        #expect(harness.mockPlayer.pauseCallCount >= 1, "Interruption began should pause playback")
    }
    
    @Test("Interruption began with shouldResume does NOT pause (system handles)")
    func interruptionBeganWithShouldResumeDoesNotPause() async throws {
        let harness = RadioPlayerControllerTestHarness()
        
        // Start playing
        try harness.controller.play(reason: "test")
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        let initialPauseCount = harness.mockPlayer.pauseCallCount
        
        // Post interruption began with shouldResume option
        let notification = makeInterruptionNotification(
            type: .began,
            options: .shouldResume
        )
        harness.notificationCenter.post(notification)
        await harness.waitForAsync()
        
        // Should NOT have called pause (system will resume automatically)
        #expect(harness.mockPlayer.pauseCallCount == initialPauseCount,
               "Interruption with shouldResume should not pause")
    }
    
    @Test("Interruption ended with shouldResume resumes playback")
    func interruptionEndedWithShouldResumeResumesPlayback() async throws {
        let harness = RadioPlayerControllerTestHarness()
        
        // Start playing then simulate interruption paused us
        try harness.controller.play(reason: "test")
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        harness.controller.pause()
        harness.simulatePlaybackStopped()
        await harness.waitForAsync()
        
        let playCountBeforeResume = harness.mockPlayer.playCallCount
        
        // Post interruption ended with shouldResume
        let notification = makeInterruptionNotification(
            type: .ended,
            options: .shouldResume
        )
        harness.notificationCenter.post(notification)
        await harness.waitForAsync()
        
        // Should have attempted to play again
        #expect(harness.mockPlayer.playCallCount > playCountBeforeResume,
               "Interruption ended with shouldResume should resume playback")
    }
    
    @Test("Route disconnected interruption logs analytics but does not pause")
    func routeDisconnectedInterruptionDoesNotPause() async throws {
        let harness = RadioPlayerControllerTestHarness()
        
        // Start playing
        try harness.controller.play(reason: "test")
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        let initialPauseCount = harness.mockPlayer.pauseCallCount
        
        // Post interruption with route disconnected reason
        let notification = makeInterruptionNotification(
            type: .began,
            reason: .routeDisconnected
        )
        harness.notificationCenter.post(notification)
        await harness.waitForAsync()
        
        // Route disconnected is not balanced by an ended notification,
        // but the current implementation does NOT pause for this case
        #expect(harness.mockPlayer.pauseCallCount == initialPauseCount,
               "Route disconnected should not call pause (handled differently)")
    }
}
#endif

// MARK: - RadioPlayerController Background/Foreground Tests

#if os(iOS)
@Suite("RadioPlayerController Background/Foreground Tests")
@MainActor
struct RadioPlayerControllerBackgroundTests {
    
    @Test("Background while not playing deactivates session")
    func backgroundWhileNotPlayingDeactivatesSession() async throws {
        let harness = RadioPlayerControllerTestHarness()
        
        // Not playing
        #expect(!harness.controller.isPlaying)
        
        // Post background notification
        harness.notificationCenter.post(
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        await harness.waitForAsync()
        
        // The session deactivation happens inside the controller
        // We can't easily verify it without mocking AVAudioSession,
        // but we verify the notification is handled without error
    }
    
    @Test("Background while playing keeps session active")
    func backgroundWhilePlayingKeepsSessionActive() async throws {
        let harness = RadioPlayerControllerTestHarness()
        
        // Start playing
        try harness.controller.play(reason: "test")
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying)
        
        let pauseCountBefore = harness.mockPlayer.pauseCallCount
        
        // Post background notification
        harness.notificationCenter.post(
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        await harness.waitForAsync()
        
        // Should NOT have paused
        #expect(harness.mockPlayer.pauseCallCount == pauseCountBefore,
               "Background while playing should not pause")
    }
    
    @Test("Foreground while playing reactivates session")
    func foregroundWhilePlayingReactivatesSession() async throws {
        let harness = RadioPlayerControllerTestHarness()
        
        // Start playing
        try harness.controller.play(reason: "test")
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying)
        
        let playCountBefore = harness.mockPlayer.playCallCount
        
        // Post foreground notification
        harness.notificationCenter.post(
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        await harness.waitForAsync()
        
        // Should have called play to reactivate
        #expect(harness.mockPlayer.playCallCount > playCountBefore,
               "Foreground while playing should reactivate playback")
    }
    
    @Test("Foreground while not playing does not start playback")
    func foregroundWhileNotPlayingDoesNotStartPlayback() async throws {
        let harness = RadioPlayerControllerTestHarness()
        
        // Not playing
        #expect(!harness.controller.isPlaying)
        let playCountBefore = harness.mockPlayer.playCallCount
        
        // Post foreground notification
        harness.notificationCenter.post(
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        await harness.waitForAsync()
        
        // Should NOT have started playback
        #expect(harness.mockPlayer.playCallCount == playCountBefore,
               "Foreground while not playing should not start playback")
    }
}
#endif

// MARK: - RadioPlayerController Route Change Tests

#if os(iOS)
@Suite("RadioPlayerController Route Change Tests")
@MainActor
struct RadioPlayerControllerRouteChangeTests {
    
    @Test("Route change is observed without error")
    func routeChangeIsObserved() async throws {
        let harness = RadioPlayerControllerTestHarness()
        
        // Start playing
        try harness.controller.play(reason: "test")
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        
        // Post route change notification
        harness.notificationCenter.post(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [
                AVAudioSessionRouteChangeReasonKey: NSNumber(value: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue)
            ]
        )
        await harness.waitForAsync()
        
        // The route change is logged but not directly handled by RadioPlayerController
        // (RadioPlayer handles its own route changes)
        // This test verifies the notification handler runs without error
    }
}
#endif

// MARK: - RadioPlayerController Playback Stalled Tests

@Suite("RadioPlayerController Playback Stalled Tests")
@MainActor
struct RadioPlayerControllerPlaybackStalledTests {
    
    @Test("Playback stalled pauses and attempts reconnect")
    func playbackStalledPausesAndReconnects() async throws {
        let harness = RadioPlayerControllerTestHarness()
        
        // Start playing
        try harness.controller.play(reason: "test")
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        #expect(harness.controller.isPlaying)
        
        let pauseCountBefore = harness.mockPlayer.pauseCallCount
        let playCountBefore = harness.mockPlayer.playCallCount
        
        // Post playback stalled notification
        harness.notificationCenter.post(
            name: .AVPlayerItemPlaybackStalled,
            object: nil
        )
        await harness.waitForAsync()
        
        // Should have paused
        #expect(harness.mockPlayer.pauseCallCount > pauseCountBefore,
               "Playback stalled should pause")
        
        // Wait for reconnect attempt (exponential backoff starts at 0.5s)
        try? await Task.sleep(for: .milliseconds(600))
        
        // Should have attempted to reconnect
        #expect(harness.mockPlayer.playCallCount > playCountBefore,
               "Playback stalled should attempt reconnect")
    }
    
    @Test("Reconnect stops if player recovers")
    func reconnectStopsIfPlayerRecovers() async throws {
        let harness = RadioPlayerControllerTestHarness()
        
        // Start playing
        try harness.controller.play(reason: "test")
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        
        // Simulate stall
        harness.notificationCenter.post(
            name: .AVPlayerItemPlaybackStalled,
            object: nil
        )
        await harness.waitForAsync()
        
        // Wait for first reconnect attempt
        try? await Task.sleep(for: .milliseconds(600))
        let playCountAfterFirstReconnect = harness.mockPlayer.playCallCount
        
        // Simulate player recovered
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        
        // Wait to see if more reconnect attempts happen
        try? await Task.sleep(for: .milliseconds(600))
        
        // Should not have made additional play calls after recovery
        // (backoff resets when isPlaying becomes true)
        #expect(harness.mockPlayer.playCallCount == playCountAfterFirstReconnect,
               "Reconnect should stop once player recovers")
    }
}

// MARK: - RadioPlayer Direct Tests

@Suite("RadioPlayer Behavior Tests")
@MainActor
struct RadioPlayerBehaviorTests {
    
    @Test("play() calls underlying player")
    func playCallsUnderlyingPlayer() async {
        let mockPlayer = MockRadioPlayer()
        let radioPlayer = RadioPlayer(
            streamURL: URL(string: "https://example.com/stream")!,
            player: mockPlayer,
            userDefaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!,
            analytics: nil,
            notificationCenter: NotificationCenter()
        )
        
        radioPlayer.play()
        
        #expect(mockPlayer.playCallCount == 1, "play() should call underlying player")
    }
    
    @Test("pause() calls underlying player")
    func pauseCallsUnderlyingPlayer() async {
        let mockPlayer = MockRadioPlayer()
        let radioPlayer = RadioPlayer(
            streamURL: URL(string: "https://example.com/stream")!,
            player: mockPlayer,
            userDefaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!,
            analytics: nil,
            notificationCenter: NotificationCenter()
        )
        
        radioPlayer.play()
        radioPlayer.pause()
        
        #expect(mockPlayer.pauseCallCount == 1, "pause() should call underlying player")
    }
    
    @Test("pause() resets stream")
    func pauseResetsStream() async {
        let mockPlayer = MockRadioPlayer()
        let radioPlayer = RadioPlayer(
            streamURL: URL(string: "https://example.com/stream")!,
            player: mockPlayer,
            userDefaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!,
            analytics: nil,
            notificationCenter: NotificationCenter()
        )
        
        radioPlayer.play()
        radioPlayer.pause()
        
        #expect(mockPlayer.replaceCurrentItemCallCount == 1, "pause() should reset stream")
    }
    
    @Test("play() while playing is idempotent")
    func playWhilePlayingIsIdempotent() async throws {
        let mockPlayer = MockRadioPlayer()
        let notificationCenter = NotificationCenter()
        let radioPlayer = RadioPlayer(
            streamURL: URL(string: "https://example.com/stream")!,
            player: mockPlayer,
            userDefaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!,
            analytics: nil,
            notificationCenter: notificationCenter
        )
        
        radioPlayer.play()
        let firstCount = mockPlayer.playCallCount
        
        // Simulate player started playing via notification
        mockPlayer.rate = 1.0
        notificationCenter.post(name: AVPlayer.rateDidChangeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(100))
        
        #expect(radioPlayer.isPlaying, "isPlaying should be true after notification")
        
        radioPlayer.play()
        #expect(mockPlayer.playCallCount == firstCount, "play() while playing should be no-op")
    }
    
    @Test("isPlaying starts as false")
    func isPlayingStartsAsFalse() async {
        let mockPlayer = MockRadioPlayer()
        let radioPlayer = RadioPlayer(
            streamURL: URL(string: "https://example.com/stream")!,
            player: mockPlayer,
            userDefaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!,
            analytics: nil,
            notificationCenter: NotificationCenter()
        )
        
        #expect(!radioPlayer.isPlaying)
    }
}

/*
 Behavioral Contract Documentation:
 
 RadioPlayerController implements these behaviors:
 
 1. play(reason:)
    - Activates audio session
    - Calls radioPlayer.play()
    - Logs analytics with reason
 
 2. pause()
    - Calls radioPlayer.pause()
    - Does NOT deactivate session (allows quick resume)
 
 3. toggle(reason:)
    - If playing: pauses and logs pause analytics
    - If paused: plays and logs play analytics
 
 4. Interruption Handling
    - Pauses on interruption began (without shouldResume)
    - Does NOT pause if shouldResume option is set
    - Resumes playback when interruption ends with shouldResume
    - Route disconnected is logged but doesn't call pause
 
 5. Route Changes
    - Observed and logged by RadioPlayerController
    - Actual handling delegated to RadioPlayer
 
 6. Remote Commands
    - Play/Pause/Toggle/Stop commands handled
 
 7. Background/Foreground
    - Deactivates session in background if not playing
    - Reactivates playback if was playing when foregrounded
    - Pauses if was not playing when foregrounded
 
 8. Playback Stalled
    - Pauses immediately
    - Attempts reconnect with exponential backoff (0.5s to 10s)
    - Stops reconnect attempts once playback resumes
 
 RadioPlayer implements these behaviors:
 
 1. play()
    - Guards against double-play (if already playing, returns early)
    - Sets UserDefaults "isPlaying" to true
    - Calls underlying player.play()
    - Starts timer for analytics
 
 2. pause()
    - Sets UserDefaults "isPlaying" to false
    - Calls underlying player.pause()
    - Resets stream by replacing current item
 
 3. isPlaying
    - Updated via AVPlayer.rateDidChangeNotification observer
    - True when player.rate > 0
 */
