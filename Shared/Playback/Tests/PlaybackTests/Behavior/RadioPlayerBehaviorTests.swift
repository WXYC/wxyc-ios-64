//
//  RadioPlayerBehaviorTests.swift
//  Playback
//
//  Direct tests for RadioPlayer internals.
//
//  Created by Jake Bromberg on 12/27/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Testing
import PlaybackTestUtilities
import AVFoundation
@testable import RadioPlayerModule

// MARK: - RadioPlayer Direct Tests

@Suite("RadioPlayer Behavior Tests")
@MainActor
struct RadioPlayerBehaviorTests {

    @Test("play() calls underlying player")
    func playCallsUnderlyingPlayer() async {
        let mockPlayer = MockPlayer()
        let radioPlayer = RadioPlayer(
            streamURL: URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!,
            player: mockPlayer,
            analytics: nil,
            notificationCenter: NotificationCenter()
        )

        radioPlayer.play()

        #expect(mockPlayer.playCallCount == 1, "play() should call underlying player")
    }

    @Test("RadioPlayer.stop() calls underlying player")
    func radioPlayerStopCallsUnderlyingPlayer() async {
        let mockPlayer = MockPlayer()
        let radioPlayer = RadioPlayer(
            streamURL: URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!,
            player: mockPlayer,
            analytics: nil,
            notificationCenter: NotificationCenter()
        )

        radioPlayer.play()
        radioPlayer.stop()

        #expect(mockPlayer.pauseCallCount == 1, "RadioPlayer.stop() should call underlying player pause")
    }

    @Test("RadioPlayer.stop() resets stream")
    func radioPlayerStopResetsStream() async {
        let mockPlayer = MockPlayer()
        let radioPlayer = RadioPlayer(
            streamURL: URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!,
            player: mockPlayer,
            analytics: nil,
            notificationCenter: NotificationCenter()
        )

        radioPlayer.play()
        radioPlayer.stop()

        #expect(mockPlayer.replaceCurrentItemCallCount == 1, "RadioPlayer.stop() should reset stream")
    }

    @Test("play() while playing is idempotent")
    func playWhilePlayingIsIdempotent() async throws {
        let mockPlayer = MockPlayer()
        let notificationCenter = NotificationCenter()
        let radioPlayer = RadioPlayer(
            streamURL: URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!,
            player: mockPlayer,
            analytics: nil,
            notificationCenter: notificationCenter
        )

        radioPlayer.play()
        let firstCount = mockPlayer.playCallCount

        // Simulate player started playing via notification
        // PlayerRateDidChangeMessage reads rate from userInfo when object isn't AVPlayer
        notificationCenter.post(
            name: AVPlayer.rateDidChangeNotification,
            object: nil,
            userInfo: ["rate": Float(1.0)]
        )
        try await Task.sleep(for: .milliseconds(100))

        #expect(radioPlayer.isPlaying, "isPlaying should be true after notification")

        radioPlayer.play()
        #expect(mockPlayer.playCallCount == firstCount, "play() while playing should be no-op")
    }

    @Test("isPlaying starts as false")
    func isPlayingStartsAsFalse() async {
        let mockPlayer = MockPlayer()
        let radioPlayer = RadioPlayer(
            streamURL: URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!,
            player: mockPlayer,
            analytics: nil,
            notificationCenter: NotificationCenter()
        )

        #expect(!radioPlayer.isPlaying)
    }
}
