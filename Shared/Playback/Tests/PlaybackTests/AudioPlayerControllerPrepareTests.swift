//
//  AudioPlayerControllerPrepareTests.swift
//  Playback
//
//  Verifies `AudioPlayerController.prepareForPlayback()` is available and safe
//  on every platform. On iOS/tvOS it eagerly configures the `.playback` category
//  and activates the audio session so the OS knows audio is imminent; on macOS
//  (native AppKit), where there is no `AVAudioSession`, it is a no-op. Either
//  way, preparing must never start playback. This is the seam that lets the
//  shared intent call sites (`IntentPlayback`, `ToggleWXYC`, `WidgetToggleWXYC`)
//  compile natively on macOS without a per-site `#if` branch.
//
//  Created by Jake Bromberg on 08/03/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import PlaybackTestUtilities
import AnalyticsTesting
@testable import Playback

@Suite("AudioPlayerController prepareForPlayback")
@MainActor
struct AudioPlayerControllerPrepareTests {
    /// `prepareForPlayback()` signals that playback is imminent; it must not
    /// itself begin playback on any platform. Runs on the macOS host too, where
    /// the call is a no-op — this is the seam that must compile under AppKit.
    @Test("prepareForPlayback does not start playback")
    func doesNotStartPlayback() {
        let controller = Self.makeController()
        #expect(controller.isPlaying == false)

        controller.prepareForPlayback()

        #expect(controller.isPlaying == false)
    }

    #if os(iOS) || os(tvOS)
    /// On iOS/tvOS the call eagerly configures the `.playback` category with the
    /// `.longFormAudio` policy and activates the session, so iOS doesn't suspend
    /// the app before an intent's stream connects.
    @Test("prepareForPlayback configures and activates the audio session")
    func configuresAndActivatesSession() {
        let mockSession = MockAudioSession()
        let controller = AudioPlayerController(
            player: MockAudioPlayerForController(),
            audioSession: mockSession,
            remoteCommandCenter: MockRemoteCommandCenter(),
            notificationCenter: .default,
            analytics: MockStructuredAnalytics()
        )

        controller.prepareForPlayback()

        #expect(mockSession.setCategoryCallCount == 1)
        #expect(mockSession.lastPolicy == .longFormAudio)
        #expect(mockSession.setActiveCallCount == 1)
        #expect(mockSession.lastActiveState == true)
    }
    #endif

    private static func makeController() -> AudioPlayerController {
        let player = MockAudioPlayerForController()
        #if os(iOS) || os(tvOS)
        return AudioPlayerController(
            player: player,
            audioSession: MockAudioSession(),
            remoteCommandCenter: MockRemoteCommandCenter(),
            notificationCenter: .default,
            analytics: MockStructuredAnalytics()
        )
        #else
        return AudioPlayerController(
            player: player,
            notificationCenter: .default,
            analytics: MockStructuredAnalytics()
        )
        #endif
    }
}
