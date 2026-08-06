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
        // inner re-arm threshold (2) is normally crossed ~2s into the park. Both
        // that inner watchdog and the controller's own 300ms outer watchdog are
        // driven off a `StartupWatchdogGate` rather than the wall clock (#787):
        // a real `Task.sleep`-based deadline races the async
        // `.waitingForConnectivity` → `isWaitingForConnectivity` →
        // `isPlayerWaitingForConnectivity` propagation, and under
        // parallel-simulator load the deadline can win, manufacturing the very
        // escalation this test exists to rule out. Gating both means neither
        // watchdog can fire until the test says so — and the test only says so
        // after proving the park has already propagated to both layers.
        let config = MP3StreamerConfiguration(url: Self.testStreamURL, connectionTimeout: 0, startupTimeout: 0.1)
        let mockHTTP = MockHTTPStreamClient()
        let mockEnginePlayer = MockAudioEnginePlayer()
        // Connect never resolves; the only signal is the manually-yielded park,
        // matching a real task that never reaches a response while offline.
        mockHTTP.shouldSucceed = true
        mockHTTP.testData = nil
        mockHTTP.nextConnectDelay = .seconds(30)

        let innerWatchdogGate = StartupWatchdogGate()
        let outerWatchdogGate = StartupWatchdogGate()

        let streamer = MP3Streamer(
            configuration: config,
            httpClient: mockHTTP,
            audioPlayer: mockEnginePlayer,
            startupWatchdogSleep: innerWatchdogGate.sleep
        )
        let mockAnalytics = MockStructuredAnalytics()
        let controller = AudioPlayerController(
            player: streamer,
            audioSession: MockAudioSession(),
            remoteCommandCenter: MockRemoteCommandCenter(),
            notificationCenter: NotificationCenter(),
            analytics: mockAnalytics,
            // The deadline value is now vestigial — the gate decides when the
            // watchdog actually fires — but kept short of the inner 1.0s
            // deadline to document the controller-preempts-inner ordering the
            // fix has to survive.
            startupWatchdogDeadline: .milliseconds(300),
            startupWatchdogSleep: outerWatchdogGate.sleep
        )

        controller.play(reason: .test)

        // Wait for the initial connect to be issued, then park it. Neither
        // watchdog can fire yet (both gates are un-released), so nothing races
        // this poll.
        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(25))
            if mockHTTP.connectCallCount >= 1 { break }
        }
        #expect(mockHTTP.connectCallCount == 1, "Precondition: the controller issued the initial connect")

        mockHTTP.yield(.waitingForConnectivity)

        // Let the park edge propagate all the way from the streamer's own flag
        // to the controller's mirror — a logic-based wait (nothing races it,
        // since both watchdogs are still gated shut), not a time-based one.
        for _ in 0..<400 {
            if streamer.isWaitingForConnectivity { break }
            await Task.yield()
        }
        #expect(streamer.isWaitingForConnectivity, "Precondition: the streamer observed the park")

        for _ in 0..<400 {
            if controller.isPlayerWaitingForConnectivity { break }
            await Task.yield()
        }
        #expect(controller.isPlayerWaitingForConnectivity, "Precondition: the controller observed the park")

        // Both preconditions are proven true before either gate is ever
        // released, so every watchdog fire from here on is guaranteed to see a
        // legitimate park — no scheduler-latency race can manufacture a false
        // escalation.

        // Drive the controller's watchdog through several deadlines: each
        // release must defer (the mirror is true), never escalate to
        // `silent_startup`.
        for _ in 0..<3 {
            await outerWatchdogGate.waitForArm()
            outerWatchdogGate.release()
        }

        // Drive the inner watchdog through both re-arms needed to cross the
        // extended-park threshold (2).
        for _ in 0..<2 {
            await innerWatchdogGate.waitForArm()
            innerWatchdogGate.release()
        }

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
        // Drain any watchdog re-arm still parked on a gate (e.g. the inner
        // watchdog's third arm, scheduled after the extended-park event fired
        // but never explicitly released) so no suspended continuation outlives
        // the test.
        innerWatchdogGate.releaseAll()
        outerWatchdogGate.releaseAll()
    }
}

#endif // os(iOS) || os(tvOS)
