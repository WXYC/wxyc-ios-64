//
//  AudioPlayerControllerGainTests.swift
//  Playback
//
//  Tests for AudioPlayerController's stream-gain boost surface: capability
//  discovery via GainBoostablePlayer and forwarding to the underlying player.
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import PlaybackTestUtilities
import AVFoundation
import Analytics
import AnalyticsTesting
import Caching
@testable import Playback
@testable import PlaybackCore

#if !os(watchOS)

@Suite("AudioPlayerController Gain Tests")
@MainActor
struct AudioPlayerControllerGainTests {

    /// Matches `AudioPlayerController.gainDecibelsKey` (private there).
    static let gainKey = "debug.streamGainDecibels"

    private func makeController(
        player: AudioPlayerProtocol,
        defaults: DefaultsStorage = InMemoryDefaults()
    ) -> AudioPlayerController {
        #if os(iOS) || os(tvOS)
        AudioPlayerController(
            player: player,
            audioSession: MockAudioSession(),
            remoteCommandCenter: MockRemoteCommandCenter(),
            notificationCenter: .default,
            analytics: MockStructuredAnalytics(),
            defaults: defaults
        )
        #else
        AudioPlayerController(
            player: player,
            notificationCenter: .default,
            analytics: MockStructuredAnalytics(),
            defaults: defaults
        )
        #endif
    }

    @Test("supportsGainBoost is false when the player can't boost")
    func nonBoostablePlayerUnsupported() {
        let controller = makeController(player: MockAudioPlayerForController())
        #expect(controller.supportsGainBoost == false)
    }

    @Test("Setting gain on an unsupported player is a safe no-op")
    func settingGainOnUnsupportedPlayerDoesNotCrash() {
        let controller = makeController(player: MockAudioPlayerForController())
        controller.gainDecibels = 6
        // No crash, and the capability still reads false.
        #expect(controller.supportsGainBoost == false)
    }

    @Test("supportsGainBoost is true for a boostable player and gain forwards")
    func boostablePlayerForwardsGain() {
        let mockPlayer = MockGainBoostablePlayer()
        let controller = makeController(player: mockPlayer)

        #expect(controller.supportsGainBoost == true)

        controller.gainDecibels = 6
        #expect(mockPlayer.gainDecibels == 6)
        #expect(controller.gainDecibels == 6)
    }

    // MARK: - Persistence

    @Test("Setting gain persists to the injected defaults")
    func gainPersistsToDefaults() {
        let defaults = InMemoryDefaults()
        let controller = makeController(player: MockGainBoostablePlayer(), defaults: defaults)

        controller.gainDecibels = 6
        #expect(defaults.float(forKey: Self.gainKey) == 6)
    }

    @Test("Persisted gain is restored on init and forwarded to the player")
    func gainRestoredOnInit() {
        let defaults = InMemoryDefaults()
        defaults.set(Float(6), forKey: Self.gainKey)

        let player = MockGainBoostablePlayer()
        let controller = makeController(player: player, defaults: defaults)

        #expect(controller.gainDecibels == 6)
        #expect(player.gainDecibels == 6)
    }

    @Test("With no persisted gain the controller falls back to the hardcoded default, forwards it, and seeds persistence")
    func noPersistedGainUsesDefault() {
        let defaults = InMemoryDefaults()
        let player = MockGainBoostablePlayer()
        let controller = makeController(player: player, defaults: defaults)

        let expected = AudioPlayerController.defaultGainDecibels
        #expect(controller.gainDecibels == expected)
        #expect(player.gainDecibels == expected)
        // The fallback is written back so the value is stable across launches.
        #expect(defaults.float(forKey: Self.gainKey) == expected)
    }
}

/// Minimal `GainBoostablePlayer` for controller capability/forwarding tests.
@MainActor
final class MockGainBoostablePlayer: GainBoostablePlayer {
    var gainDecibels: Float = 0
    var state: PlayerState = .idle
    var isPlaying: Bool = false
    var stateStream: AsyncStream<PlayerState> { AsyncStream { $0.finish() } }
    var eventStream: AsyncStream<AudioPlayerInternalEvent> { AsyncStream { $0.finish() } }
    func makeAudioBufferStream() -> AsyncStream<AVAudioPCMBuffer> { AsyncStream { $0.finish() } }
    func play() { isPlaying = true; state = .playing }
    func stop() { isPlaying = false; state = .idle }
    func installRenderTap() {}
    func removeRenderTap() {}
}

#endif
