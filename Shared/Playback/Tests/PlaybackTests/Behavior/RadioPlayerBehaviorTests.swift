//
//  RadioPlayerBehaviorTests.swift
//  PlaybackTests
//
//  Direct tests for RadioPlayer internals.
//

import Testing
import AVFoundation
@testable import RadioPlayerModule

// MARK: - RadioPlayer Direct Tests

@Suite("RadioPlayer Behavior Tests")
@MainActor
struct RadioPlayerBehaviorTests {

    @Test("play() calls underlying player")
    func playCallsUnderlyingPlayer() async {
        let mockPlayer = MockRadioPlayer()
        let radioPlayer = RadioPlayer(
            streamURL: URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!,
            player: mockPlayer,
            userDefaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!,
            analytics: nil,
            notificationCenter: NotificationCenter()
        )

        radioPlayer.play()

        #expect(mockPlayer.playCallCount == 1, "play() should call underlying player")
    }

    @Test("RadioPlayer.stop() calls underlying player")
    func radioPlayerStopCallsUnderlyingPlayer() async {
        let mockPlayer = MockRadioPlayer()
        let radioPlayer = RadioPlayer(
            streamURL: URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!,
            player: mockPlayer,
            userDefaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!,
            analytics: nil,
            notificationCenter: NotificationCenter()
        )

        radioPlayer.play()
        radioPlayer.stop()

        #expect(mockPlayer.pauseCallCount == 1, "RadioPlayer.stop() should call underlying player pause")
    }

    @Test("RadioPlayer.stop() resets stream")
    func radioPlayerStopResetsStream() async {
        let mockPlayer = MockRadioPlayer()
        let radioPlayer = RadioPlayer(
            streamURL: URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!,
            player: mockPlayer,
            userDefaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!,
            analytics: nil,
            notificationCenter: NotificationCenter()
        )

        radioPlayer.play()
        radioPlayer.stop()

        #expect(mockPlayer.replaceCurrentItemCallCount == 1, "RadioPlayer.stop() should reset stream")
    }

    @Test("play() while playing is idempotent")
    func playWhilePlayingIsIdempotent() async throws {
        let mockPlayer = MockRadioPlayer()
        let notificationCenter = NotificationCenter()
        let radioPlayer = RadioPlayer(
            streamURL: URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!,
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
            streamURL: URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!,
            player: mockPlayer,
            userDefaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!,
            analytics: nil,
            notificationCenter: NotificationCenter()
        )

        #expect(!radioPlayer.isPlaying)
    }
}
