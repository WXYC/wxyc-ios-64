//
//  ExtendedOfflineParkAnalyticsTests.swift
//  Playback
//
//  Verifies the controller forwards a player's `.extendedOfflinePark` internal
//  event into an `ExtendedOfflineParkEvent` analytics capture — the low-rate
//  observability signal for a sustained offline connect park that #697's
//  startup-watchdog gate deliberately excludes from `startup_timeout`/
//  `stream_error` (issue #699).
//
//  Created by Jake Bromberg on 07/28/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import PlaybackTestUtilities
import AnalyticsTesting
import Analytics
import AVFoundation
import Core
@testable import Playback
@testable import PlaybackCore

#if os(iOS) || os(tvOS)

@Suite("Extended Offline Park Analytics")
@MainActor
struct ExtendedOfflineParkAnalyticsTests {

    private func makeHarness(
        startupWatchdogDeadline: Duration = .seconds(15)
    ) -> (AudioPlayerController, MockAudioPlayer, MockStructuredAnalytics) {
        let streamURL = URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!
        let mockPlayer = MockAudioPlayer(url: streamURL)
        let mockAnalytics = MockStructuredAnalytics()
        let controller = AudioPlayerController(
            player: mockPlayer,
            audioSession: MockAudioSession(),
            remoteCommandCenter: MockRemoteCommandCenter(),
            notificationCenter: NotificationCenter(),
            analytics: mockAnalytics,
            startupWatchdogDeadline: startupWatchdogDeadline
        )
        return (controller, mockPlayer, mockAnalytics)
    }

    private func parkEvents(_ analytics: MockStructuredAnalytics) -> [ExtendedOfflineParkEvent] {
        analytics.typedEvents(ofType: ExtendedOfflineParkEvent.self)
    }

    private func silentStartups(_ analytics: MockStructuredAnalytics) -> [StreamErrorEvent] {
        analytics.typedEvents(ofType: StreamErrorEvent.self).filter { $0.errorType == .silentStartup }
    }

    @Test("Controller captures ExtendedOfflineParkEvent when player reports an extended park")
    func capturesExtendedOfflineParkEvent() async throws {
        let (controller, mockPlayer, mockAnalytics) = makeHarness()
        controller.play(reason: .test)
        mockAnalytics.reset()

        mockPlayer.simulateExtendedOfflinePark(duration: 24.5)

        // Drain the controller's event-observer task.
        for _ in 0..<32 { await Task.yield() }

        let events = parkEvents(mockAnalytics)
        #expect(events.count == 1, "One extendedOfflinePark event should be captured")
        let event = try #require(events.first)
        #expect(event.playerType == .mp3Streamer)
        #expect(event.parkDuration == 24.5)

        let props = try #require(event.properties)
        #expect(props["park_duration"] as? TimeInterval == 24.5)
        #expect(props["player_type"] as? String == PlayerControllerType.mp3Streamer.rawValue)
    }

    @Test("ExtendedOfflineParkEvent is named extended_offline_park for PostHog")
    func eventNameIsExtendedOfflinePark() {
        #expect(ExtendedOfflineParkEvent.name == "extended_offline_park")
    }

    /// #697's whole point is that a legitimately offline park is NOT a stream
    /// error; #699 must not regress that by pairing its own signal with one.
    @Test("An extended offline park does not also produce a StreamErrorEvent")
    func extendedOfflineParkDoesNotProduceStreamError() async throws {
        let (controller, mockPlayer, mockAnalytics) = makeHarness()
        controller.play(reason: .test)
        mockAnalytics.reset()

        mockPlayer.simulateExtendedOfflinePark(duration: 24.5)
        for _ in 0..<32 { await Task.yield() }

        #expect(mockAnalytics.typedEvents(ofType: StreamErrorEvent.self).isEmpty,
                "An extended offline park is a distinct observability signal, not a stream error — #697's exclusion must hold")
    }

    @Test("A normal first-audio success does not produce an extendedOfflinePark event")
    func firstAudioDoesNotProduceExtendedOfflinePark() async throws {
        let (controller, mockPlayer, mockAnalytics) = makeHarness()
        controller.play(reason: .test)
        mockAnalytics.reset()

        mockPlayer.simulateFirstAudio(timeToAudio: 1.4)
        for _ in 0..<32 { await Task.yield() }

        #expect(parkEvents(mockAnalytics).isEmpty)
    }

    /// The crux of #699's option-A fix: while the player reports itself parked
    /// waiting for connectivity, the controller's `silent_startup` watchdog must
    /// DEFER (re-arm) rather than escalate — escalating would emit a
    /// `silent_startup` and kick the reconnect ramp that restarts the parked
    /// streamer, defeating #697 one layer up. The player never reaches `.playing`
    /// here (`shouldAutoUpdateState = false`), so the only thing keeping the
    /// deadline from firing a `silent_startup` is the park deferral.
    @Test("Controller defers the startup watchdog while the player is parked (no silent_startup)")
    func defersStartupWatchdogWhileParked() async throws {
        let (controller, mockPlayer, mockAnalytics) = makeHarness(startupWatchdogDeadline: .milliseconds(100))
        mockPlayer.shouldAutoUpdateState = false

        controller.play(reason: .test)
        mockPlayer.simulateConnectivityWaitChanged(isWaiting: true)
        // Let the park edge land before the first deadline elapses.
        for _ in 0..<32 { await Task.yield() }

        // Span several 100ms deadlines while still parked.
        try await Task.sleep(for: .milliseconds(500))

        #expect(silentStartups(mockAnalytics).isEmpty,
                "A parked player must not escalate a silent_startup — the watchdog defers while offline (#699)")
    }

    /// The deferral must not latch: once the park resolves (connectivity edge
    /// goes false) and the player is still not producing audio, the very same
    /// watchdog must escalate `silent_startup` — the deferral bounds the offline
    /// window, it does not disable the fully-silent-startup detector forever.
    @Test("After the park resolves, the startup watchdog escalates silent_startup")
    func escalatesAfterParkResolves() async throws {
        let (controller, mockPlayer, mockAnalytics) = makeHarness(startupWatchdogDeadline: .milliseconds(100))
        mockPlayer.shouldAutoUpdateState = false

        controller.play(reason: .test)
        mockPlayer.simulateConnectivityWaitChanged(isWaiting: true)
        for _ in 0..<32 { await Task.yield() }
        try await Task.sleep(for: .milliseconds(300))
        #expect(silentStartups(mockAnalytics).isEmpty, "Precondition: deferred while parked")

        // Park resolves but audio still hasn't started — a genuine post-resume
        // starve the watchdog must now catch.
        mockPlayer.simulateConnectivityWaitChanged(isWaiting: false)

        var escalated = false
        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(25))
            if !silentStartups(mockAnalytics).isEmpty { escalated = true; break }
        }
        #expect(escalated, "Once the park resolves, a still-silent start must escalate silent_startup (#699)")
    }
}

#endif // os(iOS) || os(tvOS)
