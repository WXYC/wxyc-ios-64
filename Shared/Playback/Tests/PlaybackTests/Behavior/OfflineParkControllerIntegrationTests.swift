//
//  OfflineParkControllerIntegrationTests.swift
//  Playback
//
//  End-to-end guard for the #699 option-A fix: a REAL MP3Streamer parked
//  waiting for connectivity, driven through a REAL AudioPlayerController. The
//  isolated MP3Streamer and mock-player suites can't see the cross-layer
//  interaction that made the original PR ship a dead feature — the controller's
//  own `silent_startup` watchdog (#518) fired at its deadline and restarted the
//  parked streamer, zeroing the re-arm counter before `.extendedOfflinePark`
//  could reach its threshold. This test wires the two real layers together and
//  pins the fixed behavior: a sustained offline park emits exactly one
//  `extended_offline_park` and NO `StreamErrorEvent` (neither `silent_startup`
//  nor `startup_timeout`).
//
//  Created by Jake Bromberg on 07/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import AVFoundation
import PlaybackTestUtilities
import AnalyticsTesting
import Analytics
import Core
@testable import Playback
@testable import PlaybackCore
@testable import MP3StreamerModule

#if os(iOS) || os(tvOS)

@Suite("Offline Park Controller Integration")
@MainActor
struct OfflineParkControllerIntegrationTests {
    static let testStreamURL = URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!

    /// A real MP3Streamer parked waiting for connectivity, under a real
    /// controller whose `silent_startup` watchdog deadline (300ms) elapses
    /// *during* the park — the exact preemption the fix targets. The controller
    /// must defer that watchdog (no `silent_startup`, no reconnect restart of the
    /// streamer), the inner watchdog must defer its own `startup_timeout`, and
    /// the low-rate `.extendedOfflinePark` must still make it all the way to a
    /// captured `ExtendedOfflineParkEvent`.
    @Test("A sustained offline park fires extended_offline_park and no StreamErrorEvent, end to end")
    func sustainedParkFiresExtendedParkAndNoError() async throws {
        // startupTimeout clamps to max(0.1, connectionTimeout + 1) = 1.0s, so the
        // inner re-arm threshold (2) is crossed ~2s into the park.
        let config = MP3StreamerConfiguration(url: Self.testStreamURL, connectionTimeout: 0, startupTimeout: 0.1)
        let mockHTTP = MockHTTPStreamClient()
        let mockEnginePlayer = MockAudioEnginePlayer()
        // Connect never resolves; the only signal is the manually-yielded park,
        // matching a real task that never reaches a response while offline.
        mockHTTP.shouldSucceed = true
        mockHTTP.testData = nil
        mockHTTP.nextConnectDelay = .seconds(30)

        let streamer = MP3Streamer(configuration: config, httpClient: mockHTTP, audioPlayer: mockEnginePlayer)
        let mockAnalytics = MockStructuredAnalytics()
        let controller = AudioPlayerController(
            player: streamer,
            audioSession: MockAudioSession(),
            remoteCommandCenter: MockRemoteCommandCenter(),
            notificationCenter: NotificationCenter(),
            analytics: mockAnalytics,
            // Fires well before the inner 1.0s watchdog — reproduces the
            // controller-preempts-inner ordering the fix has to survive.
            startupWatchdogDeadline: .milliseconds(300)
        )

        controller.play(reason: .test)

        // Wait for the initial connect to be issued, then park it.
        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(25))
            if mockHTTP.connectCallCount >= 1 { break }
        }
        #expect(mockHTTP.connectCallCount == 1, "Precondition: the controller issued the initial connect")

        mockHTTP.yield(.waitingForConnectivity)
        // Let the park edge propagate streamer → controller before any deadline.
        for _ in 0..<32 { await Task.yield() }
        #expect(streamer.isWaitingForConnectivity, "Precondition: the streamer observed the park")

        // Observe across several controller deadlines AND both inner re-arms.
        var events = mockAnalytics.typedEvents(ofType: ExtendedOfflineParkEvent.self)
        for _ in 0..<200 {
            try await Task.sleep(for: .milliseconds(25))
            events = mockAnalytics.typedEvents(ofType: ExtendedOfflineParkEvent.self)
            if !events.isEmpty { break }
        }

        #expect(events.count == 1, "The sustained park must surface exactly one extended_offline_park end to end")
        if let event = events.first {
            #expect(event.playerType == .mp3Streamer)
            #expect(event.parkDuration > 0)
        }
        // The whole point of the fix: neither layer escalated. No silent_startup
        // (controller deferred) and no startup_timeout (inner deferred) — either
        // would surface here as a StreamErrorEvent.
        #expect(mockAnalytics.typedEvents(ofType: StreamErrorEvent.self).isEmpty,
                "A legitimately offline park must not escalate any StreamErrorEvent at either layer (#697/#699)")

        controller.stop(reason: .test)
    }
}

#endif // os(iOS) || os(tvOS)
