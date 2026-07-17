//
//  ReachabilityReconnectTests.swift
//  Playback
//
//  Behavior tests for reachability-gated stream reconnection (#517). The
//  controller's uncapped holding pattern (#512) used to wake on a blind timer
//  and re-attempt a connect that cannot succeed on a genuinely-down network.
//  With an injected `NetworkReachability` signal it instead idles while the path
//  is unsatisfied and fires promptly (coalesced) on the → satisfied edge, while
//  keeping the timed cadence as a fallback for "path satisfied but connect still
//  fails" (captive portal, DNS, origin down).
//
//  Created by Jake Bromberg on 07/17/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import PlaybackTestUtilities
import AVFoundation
import Core
import Analytics
import AnalyticsTesting
@testable import Playback
@testable import PlaybackCore

#if !os(watchOS)

@Suite("Reachability Reconnect Tests")
@MainActor
struct ReachabilityReconnectTests {

    // MARK: - Fixture

    private struct Fixture {
        let controller: AudioPlayerController
        let mockPlayer: MockAudioPlayer
        let mockAnalytics: MockStructuredAnalytics
        let reachability: MockNetworkReachability
    }

    /// A tiny ramp so the bounded exponential phase exhausts near-instantly and
    /// the reachability-gated holding pattern engages. `maximumWaitTime` doubles
    /// as the holding-pattern cadence.
    private static func makeFixture(
        initialSatisfied: Bool,
        holdInterval: TimeInterval = 0.05
    ) -> Fixture {
        let backoff = ExponentialBackoff(
            initialWaitTime: 0.01,
            maximumWaitTime: holdInterval,
            maximumAttempts: 1
        )
        let mockPlayer = MockAudioPlayer(url: URL(string: "https://example.com/stream")!)
        let mockAnalytics = MockStructuredAnalytics()
        let reachability = MockNetworkReachability(initialSatisfied: initialSatisfied)
        let notificationCenter = NotificationCenter()

        #if os(iOS) || os(tvOS)
        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: MockAudioSession(),
            remoteCommandCenter: MockRemoteCommandCenter(),
            notificationCenter: notificationCenter,
            analytics: mockAnalytics,
            backoffTimer: backoff,
            reachability: reachability
        )
        #else
        let controller = AudioPlayerController(
            player: mockPlayer,
            notificationCenter: notificationCenter,
            analytics: mockAnalytics,
            backoffTimer: backoff,
            reachability: reachability
        )
        #endif

        return Fixture(
            controller: controller,
            mockPlayer: mockPlayer,
            mockAnalytics: mockAnalytics,
            reachability: reachability
        )
    }

    // MARK: - Helpers

    private static func waitForAsync() async {
        for _ in 0..<32 { await Task.yield() }
    }

    private static func poll(
        until condition: @MainActor () -> Bool,
        timeout: Duration = .seconds(3)
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline, !condition() {
            await Task.yield()
        }
    }

    private static func backoffExhaustedCount(_ fixture: Fixture) -> Int {
        fixture.mockAnalytics
            .typedEvents(ofType: StreamErrorEvent.self)
            .filter { $0.errorType == .backoffExhausted }
            .count
    }

    private static func stallRecoveries(_ fixture: Fixture) -> [StallRecoveryEvent] {
        fixture.mockAnalytics.typedEvents(ofType: StallRecoveryEvent.self)
    }

    /// Drives the controller from a clean start, through a stall, through the
    /// bounded ramp (parked in `.error` so every attempt fails fast), and into
    /// the reachability-gated holding pattern. Returns once the single
    /// `backoff_exhausted` boundary event has fired.
    private static func driveIntoHoldingPattern(_ fixture: Fixture) async {
        fixture.controller.play(reason: .test)
        fixture.mockPlayer.simulateStateChange(to: .playing)
        await waitForAsync()

        // Stall the way a real player would (state + event), then park in error.
        fixture.mockPlayer.shouldAutoUpdateState = false
        fixture.mockPlayer.simulateStateChange(to: .stalled)
        fixture.mockPlayer.simulateStall()
        fixture.mockPlayer.simulateStateChange(to: .error(.connectionFailed("sabotage")))

        await poll(until: { backoffExhaustedCount(fixture) == 1 })
    }

    // MARK: - Test 1: no attempt while unsatisfied

    @Test("Holding-pattern reconnect does not attempt while the path is unsatisfied")
    func idlesWhileUnsatisfied() async {
        let fixture = Self.makeFixture(initialSatisfied: false)
        await Self.driveIntoHoldingPattern(fixture)

        // From the exhaustion boundary on, the path is unsatisfied — the holding
        // pattern must idle: no session-activation churn, no player.play().
        let playCallsAtExhaustion = fixture.mockPlayer.playCallCount

        // Wait well past several holding-pattern cadences.
        try? await Task.sleep(for: .milliseconds(400))

        #expect(fixture.mockPlayer.playCallCount == playCallsAtExhaustion,
                "No reconnect attempt should fire while the network path is unsatisfied; saw \(fixture.mockPlayer.playCallCount - playCallsAtExhaustion) extra play call(s)")

        fixture.controller.stop(reason: .test)
    }

    // MARK: - Test 2: retries promptly on the → satisfied edge

    @Test("A → satisfied transition fires a pending holding-pattern reconnect promptly")
    func retriesPromptlyOnSatisfiedEdge() async {
        let fixture = Self.makeFixture(initialSatisfied: false)
        await Self.driveIntoHoldingPattern(fixture)

        // Confirm we are idling (unsatisfied), then let the next connect succeed.
        let playCallsWhileIdle = fixture.mockPlayer.playCallCount
        try? await Task.sleep(for: .milliseconds(150))
        #expect(fixture.mockPlayer.playCallCount == playCallsWhileIdle)

        // Network returns: re-enable auto-update so the fired attempt reaches
        // .playing, then push the satisfied edge.
        fixture.mockPlayer.shouldAutoUpdateState = true
        fixture.reachability.send(satisfied: true)

        // The attempt must fire promptly on the edge, not wait out the cadence.
        await Self.poll(until: { fixture.mockPlayer.playCallCount > playCallsWhileIdle })
        #expect(fixture.mockPlayer.playCallCount > playCallsWhileIdle,
                "A → satisfied transition should fire the pending reconnect promptly")

        await Self.poll(until: { fixture.controller.isPlaying })
        #expect(fixture.controller.isPlaying,
                "The reachability-triggered reconnect should reach .playing. \(fixture.controller.debugStateSnapshot)")

        fixture.controller.stop(reason: .test)
    }

    // MARK: - Test 3: timed fallback still fires when satisfied but connect fails

    @Test("With a satisfied path but a failing connect, the timed fallback keeps retrying")
    func timedFallbackFiresWhenSatisfiedButConnectFails() async {
        // Path satisfied throughout; the player stays parked in .error so every
        // connect fails fast. A satisfied path is NOT a guarantee the host is
        // reachable, so the timed cadence must keep firing.
        let fixture = Self.makeFixture(initialSatisfied: true)
        await Self.driveIntoHoldingPattern(fixture)

        let playCallsAtExhaustion = fixture.mockPlayer.playCallCount

        // Over several cadences (0.05s each), the fallback should attempt
        // repeatedly rather than going quiet just because the path is satisfied.
        await Self.poll(until: {
            fixture.mockPlayer.playCallCount - playCallsAtExhaustion >= 2
        }, timeout: .seconds(3))

        #expect(fixture.mockPlayer.playCallCount - playCallsAtExhaustion >= 2,
                "The timed fallback must keep retrying when the path is satisfied but the connect fails; saw \(fixture.mockPlayer.playCallCount - playCallsAtExhaustion) attempt(s)")

        fixture.controller.stop(reason: .test)
    }

    // MARK: - Test 4: flapping does not produce duplicate concurrent connects

    @Test("A flapping satisfied→unsatisfied→satisfied sequence does not launch overlapping connects")
    func flappingDoesNotDuplicateConcurrentConnects() async {
        let fixture = Self.makeFixture(initialSatisfied: false)
        await Self.driveIntoHoldingPattern(fixture)

        // Idling (unsatisfied). Park the player in a non-terminal, non-playing
        // state (.stalled — the mock reports isPlaying=false and it is not
        // .isError) so the next attempt stays in flight (waitForPlayingOrError
        // polls until its 3s budget) rather than failing fast — this opens the
        // window a flap could exploit to launch a second overlapping connect.
        fixture.mockPlayer.simulateStateChange(to: .stalled)
        let playCallsWhileIdle = fixture.mockPlayer.playCallCount

        // First satisfied edge fires exactly one attempt, which goes in-flight.
        fixture.reachability.send(satisfied: true)
        await Self.poll(until: { fixture.mockPlayer.playCallCount == playCallsWhileIdle + 1 })
        #expect(fixture.mockPlayer.playCallCount == playCallsWhileIdle + 1)

        // Now flap while that attempt is still in flight. Each redundant
        // → satisfied edge must be coalesced away by the in-flight guard.
        for _ in 0..<3 {
            fixture.reachability.send(satisfied: false)
            fixture.reachability.send(satisfied: true)
            await Self.waitForAsync()
        }

        #expect(fixture.mockPlayer.playCallCount == playCallsWhileIdle + 1,
                "Flapping must not launch overlapping connects; expected exactly one in-flight attempt, saw \(fixture.mockPlayer.playCallCount - playCallsWhileIdle)")

        fixture.controller.stop(reason: .test)
    }

    // MARK: - Test 5: recovery tears down the holding pattern + monitor

    @Test("Reaching .playing leaves the holding pattern so the reachability monitor is not stranded")
    func recoveryLeavesHoldingPattern() async {
        let fixture = Self.makeFixture(initialSatisfied: false)
        await Self.driveIntoHoldingPattern(fixture)
        #expect(fixture.controller.debugStateSnapshot.contains("holdingPatternEngaged=true"),
                "Precondition: the holding pattern should be engaged while idling. \(fixture.controller.debugStateSnapshot)")

        // Let the reachability-triggered reconnect reach .playing.
        fixture.mockPlayer.shouldAutoUpdateState = true
        fixture.reachability.send(satisfied: true)
        await Self.poll(until: { fixture.controller.isPlaying })
        #expect(fixture.controller.isPlaying)

        // Reaching .playing is the universal recovery signal: the holding
        // pattern (and its pending-scoped monitor) must be torn down, not left
        // stranded across healthy playback.
        await Self.poll(until: {
            fixture.controller.debugStateSnapshot.contains("holdingPatternEngaged=false")
        })
        #expect(fixture.controller.debugStateSnapshot.contains("holdingPatternEngaged=false"),
                "Recovery must leave the holding pattern. \(fixture.controller.debugStateSnapshot)")

        // A post-recovery flap must not resurrect a reconnect: the monitor is
        // gone and the pattern disengaged, so the edge is inert.
        let playCallsAfterRecovery = fixture.mockPlayer.playCallCount
        fixture.reachability.send(satisfied: false)
        fixture.reachability.send(satisfied: true)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(fixture.mockPlayer.playCallCount == playCallsAfterRecovery,
                "A satisfied-edge after recovery must not trigger a reconnect once the holding pattern has been left")

        fixture.controller.stop(reason: .test)
    }

    // MARK: - Test 6: satisfied-edge recovery is attributed in telemetry

    @Test("A recovery driven by the → satisfied edge is credited recovery_method = reachability_resume")
    func satisfiedEdgeRecoveryAttributed() async {
        let fixture = Self.makeFixture(initialSatisfied: false)
        await Self.driveIntoHoldingPattern(fixture)

        // Wait until the monitor has subscribed and cached the initial
        // unsatisfied state, so the send below is a genuine observed
        // false → satisfied transition (attributed .reachabilityResume) rather
        // than the monitor's very first delivery (attributed .holdingFallback).
        await Self.poll(until: {
            fixture.controller.debugStateSnapshot.contains("reachabilitySatisfied=false")
        })

        // The reachability edge is what drives this reconnect to success, so the
        // recovery it produces must be attributed to the satisfied-edge path —
        // not the timed fallback and not the generic derived method.
        fixture.mockPlayer.shouldAutoUpdateState = true
        fixture.reachability.send(satisfied: true)

        await Self.poll(until: { fixture.controller.isPlaying })
        #expect(fixture.controller.isPlaying, "\(fixture.controller.debugStateSnapshot)")

        await Self.poll(until: { Self.stallRecoveries(fixture).count == 1 })
        let recoveries = Self.stallRecoveries(fixture)
        #expect(recoveries.count == 1,
                "Exactly one stall_recovery should be credited; saw \(recoveries.count)")
        #expect(recoveries.first?.recoveryMethod == .reachabilityResume,
                "A satisfied-edge recovery must be attributed .reachabilityResume; got \(String(describing: recoveries.first?.recoveryMethod))")

        fixture.controller.stop(reason: .test)
    }

    // MARK: - Test 7: timed-fallback recovery is attributed in telemetry

    @Test("A recovery driven by the timed fallback is credited recovery_method = holding_fallback")
    func timedFallbackRecoveryAttributed() async {
        // Path satisfied throughout, so recovery comes from the flat timed
        // cadence rather than a → satisfied edge.
        let fixture = Self.makeFixture(initialSatisfied: true)
        await Self.driveIntoHoldingPattern(fixture)

        // Let the next timed fallback tick reconnect successfully.
        fixture.mockPlayer.shouldAutoUpdateState = true

        await Self.poll(until: { fixture.controller.isPlaying })
        #expect(fixture.controller.isPlaying, "\(fixture.controller.debugStateSnapshot)")

        await Self.poll(until: { Self.stallRecoveries(fixture).count == 1 })
        let recoveries = Self.stallRecoveries(fixture)
        #expect(recoveries.count == 1,
                "Exactly one stall_recovery should be credited; saw \(recoveries.count)")
        #expect(recoveries.first?.recoveryMethod == .holdingFallback,
                "A timed-fallback recovery must be attributed .holdingFallback; got \(String(describing: recoveries.first?.recoveryMethod))")

        fixture.controller.stop(reason: .test)
    }
}

#endif
