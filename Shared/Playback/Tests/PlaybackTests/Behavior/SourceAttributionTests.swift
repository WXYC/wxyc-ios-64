//
//  SourceAttributionTests.swift
//  Playback
//
//  First-class source-surface attribution on play/pause events (#668).
//  Verifies that PlaybackStartedEvent/PlaybackStoppedEvent carry a clean,
//  low-cardinality `source` for a representative set of entry points, and
//  that user pauses — which previously shipped no attribution at all — now
//  carry the real `tearDown(reason:)`-derived source.
//
//  Created by Jake Bromberg on 07/25/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import PlaybackTestUtilities
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif
@testable import Playback
@testable import PlaybackCore
@testable import RadioPlayerModule

@Suite("Source Attribution Tests")
@MainActor
struct SourceAttributionTests {

    // MARK: - Play entry points

    @Test("CarPlay play attributes source .carPlay", arguments: PlayerControllerTestCase.allCases)
    func carPlayPlayAttributesCarPlay(testCase: PlayerControllerTestCase) async throws {
        let harness = PlayerControllerTestHarness.make(for: testCase)

        try harness.controller.play(reason: .carPlay)

        #expect(harness.mockAnalytics.startedEvents.last?.source == PlaybackSource.carPlay.rawValue)
    }

    @Test("Siri's PlayWXYC intent attributes source .siri", arguments: PlayerControllerTestCase.allCases)
    func playIntentAttributesSiri(testCase: PlayerControllerTestCase) async throws {
        let harness = PlayerControllerTestHarness.make(for: testCase)

        try harness.controller.play(reason: .playIntent)

        #expect(harness.mockAnalytics.startedEvents.last?.source == PlaybackSource.siri.rawValue)
    }

    @Test("The watch's play/pause button attributes source .watch", arguments: PlayerControllerTestCase.allCases)
    func watchPlayPauseAttributesWatch(testCase: PlayerControllerTestCase) async throws {
        let harness = PlayerControllerTestHarness.make(for: testCase)

        try harness.controller.play(reason: .watchPlayPause)

        #expect(harness.mockAnalytics.startedEvents.last?.source == PlaybackSource.watch.rawValue)
    }

    @Test("The widget's dedicated reason attributes source .widget", arguments: PlayerControllerTestCase.allCases)
    func widgetToggleAttributesWidget(testCase: PlayerControllerTestCase) async throws {
        let harness = PlayerControllerTestHarness.make(for: testCase)

        try harness.controller.play(reason: .widgetToggle)

        #expect(harness.mockAnalytics.startedEvents.last?.source == PlaybackSource.widget.rawValue)
    }

    // MARK: - Pause entry points (the core #668 regression: previously unattributed)

    @Test("A remote-command pause (toggle-to-stop) attributes source .remote", arguments: PlayerControllerTestCase.allCases)
    func remoteCommandPauseAttributesRemote(testCase: PlayerControllerTestCase) async throws {
        // AudioPlayerController's dedicated `commandCenter.pauseCommand` target
        // and RadioPlayerController's `remotePauseOrStopCommand` both funnel
        // through the same private stop-and-capture helper `toggle(reason:)`
        // uses (see `stop(reason:)` in each controller), so
        // driving this via `toggle(reason: .remotePauseCommand)` exercises the
        // identical code path a real Lock Screen/Control Center pause tap
        // would — `MPRemoteCommandEvent` has no public initializer, so the
        // command-center target closures themselves can't be invoked directly
        // from a unit test.
        let harness = PlayerControllerTestHarness.make(for: testCase)
        try harness.controller.play(reason: .remotePlayCommand)

        try harness.controller.toggle(reason: .remotePauseCommand)

        #expect(harness.mockAnalytics.stoppedEvents.last?.source == PlaybackSource.remote.rawValue)
    }

    @Test("A genuine user stop attributes the real reason's source, not unknown", arguments: PlayerControllerTestCase.allCases)
    func userStopAttributesRealSource(testCase: PlayerControllerTestCase) async throws {
        // Before #668, `toggle(reason:)`'s stop branch captured a
        // `PlaybackStoppedEvent` with no source at all — the reason was known
        // at the call site but silently dropped. This is the regression test
        // for that gap: a CarPlay-initiated pause must report `.carPlay`, not
        // `.unknown`.
        let harness = PlayerControllerTestHarness.make(for: testCase)
        try harness.controller.play(reason: .carPlay)

        try harness.controller.toggle(reason: .carPlay)

        #expect(harness.mockAnalytics.stoppedEvents.last?.source == PlaybackSource.carPlay.rawValue,
               "A user-initiated stop must carry the real source instead of dropping it")
    }

    // MARK: - Auto-resume (system-driven, not a user action)

    #if os(iOS)
    @Test("Interruption-began stop and interruption-ended resume are both tagged .auto", arguments: PlayerControllerTestCase.allCases)
    func interruptionAutoResumeIsTaggedAuto(testCase: PlayerControllerTestCase) async throws {
        let harness = PlayerControllerTestHarness.make(for: testCase)

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        harness.mockAnalytics.reset()

        harness.postInterruptionBegan(shouldResume: true)
        await harness.waitForAsync()

        #expect(harness.mockAnalytics.stoppedEvents.last?.source == PlaybackSource.auto.rawValue,
               "Interruption-began is system-driven, not a user pause")

        harness.postInterruptionEnded(shouldResume: true)
        await harness.waitForAsync()

        #expect(harness.mockAnalytics.startedEvents.last?.source == PlaybackSource.auto.rawValue,
               "Auto-resume after an interruption is system-driven, not a user play")

        harness.controller.stop()
    }

    @Test("Route-disconnect auto-resume is tagged .auto")
    func routeDisconnectAutoResumeIsTaggedAuto() async throws {
        // Only AudioPlayerController handles route changes with analytics
        // (see AnalyticsIntegrationTests.routeDisconnectedReportsCorrectReason).
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        harness.controller.play()
        harness.simulatePlaybackStarted()
        await harness.waitForAsync()
        harness.mockAnalytics.reset()

        harness.postRouteChange(reason: .oldDeviceUnavailable)
        await harness.waitForAsync()

        #expect(harness.mockAnalytics.stoppedEvents.last?.source == PlaybackSource.auto.rawValue)

        harness.postRouteChange(reason: .newDeviceAvailable)
        await harness.waitForAsync()

        #expect(harness.mockAnalytics.startedEvents.last?.source == PlaybackSource.auto.rawValue)

        harness.controller.stop()
    }
    #endif

    // MARK: - Default

    @Test("A reason with no mapping defaults source to .unknown rather than crashing", arguments: PlayerControllerTestCase.allCases)
    func unmappedReasonDefaultsToUnknown(testCase: PlayerControllerTestCase) async throws {
        let harness = PlayerControllerTestHarness.make(for: testCase)

        try harness.controller.play(reason: PlaybackReason(rawValue: "a reason nobody mapped"))

        #expect(harness.mockAnalytics.startedEvents.last?.source == PlaybackSource.unknown.rawValue)
    }
}
