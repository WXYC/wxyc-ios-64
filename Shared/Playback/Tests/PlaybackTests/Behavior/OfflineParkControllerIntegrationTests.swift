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
        // Both the inner (streamer) and outer (controller) startup watchdogs are
        // driven off a `StartupWatchdogGate` rather than the wall clock (#787):
        // a real `Task.sleep`-based deadline races the async
        // `.waitingForConnectivity` → `isWaitingForConnectivity` →
        // `isPlayerWaitingForConnectivity` propagation, and under
        // parallel-simulator load the deadline can win, manufacturing the very
        // escalation this test exists to rule out. Gating both means neither
        // watchdog can fire until the test says so — and the test only says so
        // after proving the park has already propagated to both layers.
        //
        // The two deadlines no longer decide *when* a watchdog fires, but they
        // are still what each watchdog asks its gate for, so `requestedDurations`
        // keeps the arithmetic behind them under test rather than merely
        // configured: `startupTimeout` still has to clamp to
        // `max(0.1, connectionTimeout + 1)` = 1.0s, and the controller's deadline
        // still has to sit short of it — that ordering is what puts an outer fire
        // between the inner re-arms, which is the preemption the fix survives.
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
            startupWatchdogDeadline: .milliseconds(300),
            startupWatchdogSleep: outerWatchdogGate.sleep
        )

        controller.play(reason: .test)

        // Wait for the initial connect to be issued, then park it. Neither
        // watchdog can fire yet (both gates are un-released), so nothing races
        // these polls: every deadline below bounds a hang, it never decides an
        // assertion.
        await pollUntil { mockHTTP.connectCallCount >= 1 }
        #expect(mockHTTP.connectCallCount == 1, "Precondition: the controller issued the initial connect")

        mockHTTP.yield(.waitingForConnectivity)

        // Let the park edge propagate all the way from the streamer's own flag
        // to the controller's mirror.
        await pollUntil { streamer.isWaitingForConnectivity }
        #expect(streamer.isWaitingForConnectivity, "Precondition: the streamer observed the park")

        await pollUntil { controller.isPlayerWaitingForConnectivity }
        #expect(controller.isPlayerWaitingForConnectivity, "Precondition: the controller observed the park")

        // Both preconditions are proven true before either gate is ever
        // released, so every watchdog fire from here on is guaranteed to see a
        // legitimate park — no scheduler-latency race can manufacture a false
        // escalation.

        // Interleave the two watchdogs, because the interaction this suite
        // exists for is an ordering one: the original bug had the controller's
        // watchdog fire *between* the streamer's re-arms and restart the parked
        // streamer, zeroing `offlineParkReArmCount` before it could reach the
        // threshold of 2. Firing all of one layer and then all of the other
        // would leave that counter at 0 during every outer fire and never
        // reproduce it. Two rounds put an outer fire on each side of the first
        // re-arm:
        //
        //   round 1 — outer fires with the counter at 0, must defer and re-arm
        //             inner fires, counter → 1
        //   round 2 — outer fires with the counter at 1: the exact preemption
        //             inner fires, counter → 2 == threshold, so the event lands
        for _ in 0..<2 {
            try await outerWatchdogGate.waitForArm()
            outerWatchdogGate.release()
            try await innerWatchdogGate.waitForArm()
            innerWatchdogGate.release()
        }

        // Every release above resumed a genuinely armed watchdog, and both
        // watchdogs armed again after their last fire. Without this, the
        // `StreamErrorEvent.isEmpty` assertion below would be satisfied equally
        // by "deferred correctly" and by "silently stopped firing" — a watchdog
        // that quietly gave up emits nothing either.
        #expect(outerWatchdogGate.fireCount == 2, "The controller's watchdog must have fired at both deadlines")
        #expect(innerWatchdogGate.fireCount == 2, "The streamer's watchdog must have fired at both deadlines")
        try await outerWatchdogGate.waitForArm()
        try await innerWatchdogGate.waitForArm()

        // The deadlines the two watchdogs asked for. Inert as timing now, but
        // still the arithmetic the fix depends on: the clamp, and the outer
        // deadline sitting inside the inner one.
        #expect(Set(innerWatchdogGate.requestedDurations) == [.seconds(1)],
                "startupTimeout must clamp to max(0.1, connectionTimeout + 1) = 1.0s")
        #expect(Set(outerWatchdogGate.requestedDurations) == [.milliseconds(300)],
                "The controller's deadline must stay inside the streamer's, so it preempts rather than trails")

        await pollUntil { !mockAnalytics.typedEvents(ofType: ExtendedOfflineParkEvent.self).isEmpty }
        let events = mockAnalytics.typedEvents(ofType: ExtendedOfflineParkEvent.self)

        #expect(events.count == 1, "The sustained park must surface exactly one extended_offline_park end to end")
        if let event = events.first {
            #expect(event.playerType == .mp3Streamer)
            // Measures the span from the park edge to the threshold crossing.
            // With the gate driving the fires that is a handful of scheduler
            // hops rather than the ~2s a wall-clock run would report, so this
            // pins that the timer is running and attributed, not its magnitude.
            #expect(event.parkDuration > 0)
        }
        // The whole point of the fix: neither layer escalated. No silent_startup
        // (controller deferred) and no startup_timeout (inner deferred) — either
        // would surface here as a StreamErrorEvent.
        #expect(mockAnalytics.typedEvents(ofType: StreamErrorEvent.self).isEmpty,
                "A legitimately offline park must not escalate any StreamErrorEvent at either layer (#697/#699)")

        controller.tearDown(reason: .test)
        // Drain any watchdog re-arm still parked on a gate (e.g. the inner
        // watchdog's third arm, scheduled after the extended-park event fired
        // but never explicitly released) so no suspended continuation outlives
        // the test.
        innerWatchdogGate.releaseAll()
        outerWatchdogGate.releaseAll()
    }
}

#endif // os(iOS) || os(tvOS)
