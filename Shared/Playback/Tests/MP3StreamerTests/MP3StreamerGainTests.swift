//
//  MP3StreamerGainTests.swift
//  Playback
//
//  Tests for the debug stream-gain boost: AudioEnginePlayer's decibel gain node
//  and MP3Streamer's GainBoostablePlayer forwarding.
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import PlaybackTestUtilities
import Foundation
@preconcurrency import AVFoundation
import PlaybackCore
@testable import MP3StreamerModule

#if !os(watchOS)

@Suite("MP3Streamer Gain Tests")
@MainActor
struct MP3StreamerGainTests {
    static let testStreamURL = URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!

    // MARK: - AudioEnginePlayer decibel gain node
    //
    // These construct an AudioEnginePlayer but never call play(), so no audio
    // hardware is activated — the gain getter/setter are pure Swift over the
    // stored, clamped value and do not require a running engine.

    @Test("AudioEnginePlayer default gain is 0 dB (unity, no boost)")
    func defaultGainIsZero() {
        let player = AudioEnginePlayer(format: TestAudioBufferFactory.makeStandardFormat())
        #expect(player.gainDecibels == 0)
    }

    @Test("AudioEnginePlayer gain round-trips")
    func gainRoundTrips() {
        let player = AudioEnginePlayer(format: TestAudioBufferFactory.makeStandardFormat())
        player.gainDecibels = 6
        #expect(player.gainDecibels == 6)
    }

    @Test("AudioEnginePlayer clamps gain to the AVAudioUnitEQ range (-96...24 dB)")
    func gainClampsToValidRange() {
        let player = AudioEnginePlayer(format: TestAudioBufferFactory.makeStandardFormat())
        player.gainDecibels = 100
        #expect(player.gainDecibels == 24)
        player.gainDecibels = -200
        #expect(player.gainDecibels == -96)
    }

    // MARK: - MP3Streamer forwarding

    @Test("MP3Streamer forwards gain to the audio engine player")
    func streamerForwardsGain() {
        let mockPlayer = MockAudioEnginePlayer()
        let streamer = MP3Streamer(
            configuration: MP3StreamerConfiguration(url: Self.testStreamURL),
            httpClient: MockHTTPStreamClient(),
            audioPlayer: mockPlayer
        )

        #expect(streamer.gainDecibels == 0)
        streamer.gainDecibels = 6
        #expect(mockPlayer.gainDecibels == 6)
        #expect(streamer.gainDecibels == 6)
    }

    @Test("MP3Streamer is discoverable as a GainBoostablePlayer")
    func streamerIsGainBoostable() {
        let streamer = MP3Streamer(
            configuration: MP3StreamerConfiguration(url: Self.testStreamURL),
            httpClient: MockHTTPStreamClient(),
            audioPlayer: MockAudioEnginePlayer()
        )
        #expect((streamer as? GainBoostablePlayer) != nil)
    }
}

#endif
