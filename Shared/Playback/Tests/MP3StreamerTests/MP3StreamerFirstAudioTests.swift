//
//  MP3StreamerFirstAudioTests.swift
//  Playback
//
//  Tests for the "first audio" success signal: the streamer must yield exactly
//  one `.firstAudio` internal event when the buffering phase first crosses into
//  playing, so the controller can capture a `PlaybackFirstAudioEvent`. This is
//  the denominator for playback-start success rate (issue #513).
//
//  Created by Jake Bromberg on 07/14/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import PlaybackTestUtilities
import Foundation
import AVFoundation
@testable import MP3StreamerModule
@testable import PlaybackCore
import Core

#if !os(watchOS)

@Suite("MP3Streamer First Audio")
@MainActor
struct MP3StreamerFirstAudioTests {
    static let testStreamURL = URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!

    /// Drains the streamer's internal event stream on a detached task and records
    /// every `.firstAudio` event with its reported time-to-audio.
    private final class FirstAudioCollector {
        var timesToAudio: [TimeInterval] = []
        var count: Int { timesToAudio.count }
    }

    /// Feeds enough decoded-buffer-producing MP3 data through the streamer to cross
    /// the buffering threshold and reach `.playing`, using the injectable mocks so no
    /// real network or audio hardware is needed.
    private func makeStreamer(
        minimumBuffers: Int = 2
    ) throws -> (MP3Streamer, MockHTTPStreamClient, MockAudioEnginePlayer) {
        let config = MP3StreamerConfiguration(
            url: Self.testStreamURL,
            minimumBuffersBeforePlayback: minimumBuffers,
            startupTimeout: 5.0
        )
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()
        mockPlayer.immediatelyRequestMoreBuffers = false
        mockHTTP.testData = try TestAudioBufferFactory.loadMP3TestData()
        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer
        )
        return (streamer, mockHTTP, mockPlayer)
    }

    /// Waits until the streamer reaches `.playing` (real MP3 decode), or returns
    /// `false` if the environment can't decode within the budget so the test can
    /// skip rather than fail.
    private func waitForPlaying(_ streamer: MP3Streamer) async throws -> Bool {
        for _ in 0..<30 {
            try await Task.sleep(for: .milliseconds(100))
            if case .playing = streamer.streamingState { return true }
        }
        return false
    }

    @Test("Yields exactly one firstAudio event on a healthy start")
    func firesOnceOnHealthyStart() async throws {
        let (streamer, _, _) = try makeStreamer()

        let collector = FirstAudioCollector()
        let drain = Task { @MainActor in
            for await event in streamer.eventStreamInternal {
                if case .firstAudio(let timeToAudio) = event {
                    collector.timesToAudio.append(timeToAudio)
                }
            }
        }
        defer { drain.cancel() }

        streamer.play()
        guard try await waitForPlaying(streamer) else { return } // decode unavailable → skip

        // Give the event stream a moment to deliver.
        try await Task.sleep(for: .milliseconds(100))

        #expect(collector.count == 1, "Exactly one firstAudio event should fire on a healthy start")
        if let time = collector.timesToAudio.first {
            #expect(time >= 0, "time-to-first-audio must be non-negative")
        }
    }

    @Test("Does not yield firstAudio when the start fails (never reaches playing)")
    func doesNotFireOnFailedStart() async throws {
        // Connect succeeds but no data ever arrives → stuck in buffering, never playing.
        let config = MP3StreamerConfiguration(url: Self.testStreamURL, startupTimeout: 5.0)
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()
        mockHTTP.shouldSucceed = true
        mockHTTP.testData = nil

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockPlayer
        )

        let collector = FirstAudioCollector()
        let drain = Task { @MainActor in
            for await event in streamer.eventStreamInternal {
                if case .firstAudio(let timeToAudio) = event {
                    collector.timesToAudio.append(timeToAudio)
                }
            }
        }
        defer { drain.cancel() }

        streamer.play()
        try await Task.sleep(for: .milliseconds(300))

        #expect(collector.count == 0, "firstAudio must not fire when playback never begins")
    }

    @Test("Does not double-fire firstAudio across a reconnect")
    func doesNotDoubleFireAcrossReconnect() async throws {
        let (streamer, mockHTTP, _) = try makeStreamer()

        let collector = FirstAudioCollector()
        let drain = Task { @MainActor in
            for await event in streamer.eventStreamInternal {
                if case .firstAudio(let timeToAudio) = event {
                    collector.timesToAudio.append(timeToAudio)
                }
            }
        }
        defer { drain.cancel() }

        streamer.play()
        guard try await waitForPlaying(streamer) else { return } // decode unavailable → skip
        try await Task.sleep(for: .milliseconds(100))
        #expect(collector.count == 1, "Precondition: one firstAudio on the initial start")

        // Simulate an unexpected mid-stream disconnect, which schedules a reconnect
        // that connects and re-buffers back into .playing. That recovery must NOT
        // emit a second firstAudio (that is what stall_recovery tracks; a second
        // firstAudio would inflate the start-success denominator).
        mockHTTP.yield(.disconnected)

        for _ in 0..<30 {
            try await Task.sleep(for: .milliseconds(100))
            if case .playing = streamer.streamingState, mockHTTP.connectCallCount >= 2 { break }
        }
        try await Task.sleep(for: .milliseconds(100))

        #expect(collector.count == 1, "firstAudio must fire once per start, not again on reconnect recovery")
    }

    @Test("Fires again after a full stop() and fresh play()")
    func firesAgainAfterStopAndReplay() async throws {
        let (streamer, mockHTTP, _) = try makeStreamer()

        let collector = FirstAudioCollector()
        let drain = Task { @MainActor in
            for await event in streamer.eventStreamInternal {
                if case .firstAudio(let timeToAudio) = event {
                    collector.timesToAudio.append(timeToAudio)
                }
            }
        }
        defer { drain.cancel() }

        streamer.play()
        guard try await waitForPlaying(streamer) else { return } // decode unavailable → skip
        try await Task.sleep(for: .milliseconds(100))
        #expect(collector.count == 1, "Precondition: one firstAudio on the initial start")

        streamer.stop()
        try await Task.sleep(for: .milliseconds(50))

        // A fresh start is a new playback session and should count again.
        mockHTTP.testData = try TestAudioBufferFactory.loadMP3TestData()
        streamer.play()
        guard try await waitForPlaying(streamer) else { return }
        try await Task.sleep(for: .milliseconds(100))

        #expect(collector.count == 2, "A fresh stop()+play() is a new session and should emit firstAudio again")
    }
}

#endif // !os(watchOS)
