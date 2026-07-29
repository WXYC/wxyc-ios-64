//
//  MP3StreamerOfflineParkTelemetryTests.swift
//  Playback
//
//  Tests for the #699 observability gap left by #697: the startup watchdog no
//  longer tears down a task that is legitimately parked waiting for network
//  connectivity, but that trade produced a totally silent multi-minute hang —
//  no `startup_timeout`, no analytics event at all. These tests pin the
//  distinct, low-rate `.extendedOfflinePark` signal that closes that gap: it
//  must fire exactly once per sustained park episode, must NOT fire for a
//  normal connect, and must NOT fire for the connected-but-starved (IOS-31)
//  path that the watchdog's `startup_timeout` escalation still owns.
//
//  Created by Jake Bromberg on 07/28/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import PlaybackTestUtilities
import Foundation
import AVFoundation
import Core
@testable import MP3StreamerModule
@testable import PlaybackCore

#if !os(watchOS)

@Suite("MP3Streamer Offline Park Telemetry")
@MainActor
struct MP3StreamerOfflineParkTelemetryTests {
    static let testStreamURL = URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!

    /// Drains the streamer's internal event stream and records every
    /// `.extendedOfflinePark` and `.error` event, so tests can assert both that
    /// the new signal fires and that it stays distinct from the `startup_timeout`
    /// class (#697's exclusion must not regress).
    private final class EventCollector {
        var parkDurations: [TimeInterval] = []
        var errors: [Error] = []
    }

    private func drain(_ streamer: MP3Streamer, into collector: EventCollector) -> Task<Void, Never> {
        Task { @MainActor in
            for await event in streamer.eventStreamInternal {
                switch event {
                case .extendedOfflinePark(let duration):
                    collector.parkDurations.append(duration)
                case .error(let error):
                    collector.errors.append(error)
                default:
                    break
                }
            }
        }
    }

    /// The core #699 case: a task parked waiting for connectivity long enough
    /// that the watchdog has re-armed repeatedly must surface exactly one
    /// `.extendedOfflinePark` event — not zero (the current silent hang) and
    /// not one per re-arm (which would just be `startup_timeout` noise wearing
    /// a different name).
    @Test("Fires exactly one extendedOfflinePark event for a sustained park")
    func firesOnceForSustainedPark() async throws {
        let config = MP3StreamerConfiguration(url: Self.testStreamURL, connectionTimeout: 0, startupTimeout: 0.1)
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()

        // Held open indefinitely — the only signal the streamer ever sees is
        // the manually-yielded `.waitingForConnectivity` below, matching a real
        // parked task that never reaches `didReceive response` while offline.
        mockHTTP.shouldSucceed = true
        mockHTTP.testData = nil
        mockHTTP.nextConnectDelay = .seconds(30)

        let streamer = MP3Streamer(configuration: config, httpClient: mockHTTP, audioPlayer: mockPlayer)
        let collector = EventCollector()
        let drainTask = drain(streamer, into: collector)
        defer { drainTask.cancel() }

        streamer.play()

        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(25))
            if mockHTTP.connectCallCount >= 1 { break }
        }
        #expect(mockHTTP.connectCallCount == 1, "Precondition: the initial connect was issued")

        mockHTTP.yield(.waitingForConnectivity)

        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(25))
            if streamer.isWaitingForConnectivity { break }
        }
        #expect(streamer.isWaitingForConnectivity, "Precondition: the streamer observed the park")

        // Let several clamped ~1.0s watchdog deadlines elapse while still
        // parked — long enough for the re-arm threshold to be crossed.
        for _ in 0..<200 {
            try await Task.sleep(for: .milliseconds(25))
            if !collector.parkDurations.isEmpty { break }
        }

        #expect(collector.parkDurations.count == 1, "Exactly one extendedOfflinePark event should fire for a single sustained park episode")
        if let duration = collector.parkDurations.first {
            #expect(duration > 0, "The reported park duration should be positive")
        }
        #expect(collector.errors.isEmpty, "No startup_timeout (or any other) error should accompany the park signal — #697's exclusion must hold")

        // Keep observing past the first emission — long enough to cross at
        // least one more of the clamped ~1.0s watchdog re-arms while still
        // parked — and confirm the signal does not repeat.
        try await Task.sleep(for: .milliseconds(1500))
        #expect(collector.parkDurations.count == 1, "The signal must not repeat on every subsequent re-arm — one per episode, not one per 12s tick")
    }

    /// A normal connect — never parked — must never emit the park signal.
    @Test("Does not fire for a normal connect")
    func doesNotFireForNormalConnect() async throws {
        let config = MP3StreamerConfiguration(url: Self.testStreamURL, minimumBuffersBeforePlayback: 2, startupTimeout: 5.0)
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()
        mockHTTP.testData = try TestAudioBufferFactory.loadMP3TestData()

        let streamer = MP3Streamer(configuration: config, httpClient: mockHTTP, audioPlayer: mockPlayer)
        let collector = EventCollector()
        let drainTask = drain(streamer, into: collector)
        defer { drainTask.cancel() }

        streamer.play()

        try await Task.sleep(for: .milliseconds(500))

        #expect(collector.parkDurations.isEmpty, "A normal connect must never emit extendedOfflinePark")
    }

    /// The connected-but-starved path (Sentry IOS-31): the stream connects but
    /// never crosses the buffering threshold, so the watchdog escalates through
    /// its existing `startup_timeout` path. `isWaitingForConnectivity` is never
    /// set here, so the park signal must stay silent — this is the watchdog's
    /// original job, not the offline-park observability gap.
    @Test("Does not fire for the connected-but-starved (IOS-31) path")
    func doesNotFireForConnectedButStarved() async throws {
        let config = MP3StreamerConfiguration(url: Self.testStreamURL, connectionTimeout: 0, startupTimeout: 0.1)
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()
        // Connects immediately (no data), then simply never buffers further —
        // starved while connected, the case #697's gate must not touch.
        mockHTTP.shouldSucceed = true
        mockHTTP.testData = nil

        let streamer = MP3Streamer(configuration: config, httpClient: mockHTTP, audioPlayer: mockPlayer)
        let collector = EventCollector()
        let drainTask = drain(streamer, into: collector)
        defer { drainTask.cancel() }

        streamer.play()

        // The startup watchdog is clamped to max(0.1, connectionTimeout + 1) =
        // 1.0s, so budget well past it (up to ~4s) rather than racing the ~1.0s
        // deadline with a ~1.0s wait window.
        for _ in 0..<160 {
            try await Task.sleep(for: .milliseconds(25))
            if !collector.errors.isEmpty { break }
        }

        #expect(!collector.errors.isEmpty, "Precondition: the connected-but-starved path still escalates via startup_timeout")
        #expect(collector.parkDurations.isEmpty, "The connected-but-starved path must not emit extendedOfflinePark")
    }

    /// A park that resolves (connectivity returns) and is later followed by a
    /// fresh, independent park must be able to fire the signal again — the
    /// once-per-episode guard must reset with the episode, not latch forever
    /// for the life of the streamer.
    @Test("Fires again for a second, independent park episode after the first resolves")
    func firesAgainForIndependentEpisode() async throws {
        let config = MP3StreamerConfiguration(url: Self.testStreamURL, connectionTimeout: 0, startupTimeout: 0.1)
        let mockHTTP = MockHTTPStreamClient()
        let mockPlayer = MockAudioEnginePlayer()
        mockHTTP.shouldSucceed = true
        mockHTTP.testData = nil
        mockHTTP.nextConnectDelay = .seconds(30)

        let streamer = MP3Streamer(configuration: config, httpClient: mockHTTP, audioPlayer: mockPlayer)
        let collector = EventCollector()
        let drainTask = drain(streamer, into: collector)
        defer { drainTask.cancel() }

        streamer.play()

        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(25))
            if mockHTTP.connectCallCount >= 1 { break }
        }

        // First park: parked, wait for the signal, then resolve.
        mockHTTP.yield(.waitingForConnectivity)
        for _ in 0..<200 {
            try await Task.sleep(for: .milliseconds(25))
            if !collector.parkDurations.isEmpty { break }
        }
        #expect(collector.parkDurations.count == 1, "Precondition: the first episode fired once")

        // Connectivity returns — the original task's response finally arrives.
        mockHTTP.yield(.connected)
        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(25))
            if !streamer.isWaitingForConnectivity { break }
        }
        #expect(!streamer.isWaitingForConnectivity, "Precondition: the first park resolved")

        // Snapshot the connect count before restarting so the second episode's
        // fresh connect is measured as a delta. Resolving via `.connected` leaves
        // the startup watchdog armed in `.buffering`; it can escalate a
        // `startup_timeout` and kick a reconnect before `stop()` cancels it, so a
        // bare `>= 2` gate could be satisfied by that reconnect rather than the
        // intended second `play()`.
        let connectsBeforeSecondPlay = mockHTTP.connectCallCount

        // Force a second, independent connect attempt by restarting.
        streamer.stop()
        streamer.play()
        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(25))
            if mockHTTP.connectCallCount > connectsBeforeSecondPlay { break }
        }

        mockHTTP.yield(.waitingForConnectivity)
        for _ in 0..<200 {
            try await Task.sleep(for: .milliseconds(25))
            if collector.parkDurations.count >= 2 { break }
        }

        #expect(collector.parkDurations.count == 2, "A second, independent park episode must fire its own extendedOfflinePark event")
    }
}

#endif // !os(watchOS)
