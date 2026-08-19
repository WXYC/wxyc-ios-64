//
//  HandoffActivityManagerTests.swift
//  WXYC
//
//  Unit tests for HandoffActivityManager (the playback-gated Handoff
//  NSUserActivity lifecycle) and the WXYCUserActivity.continuationReason(...)
//  seam that attributes a continued activity to a PlaybackReason.
//
//  Created by Jake Bromberg on 07/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import Core
import PlaybackCore
@testable import WXYC

// MARK: - Handoff Activity Lifecycle Tests

@Suite("Handoff activity lifecycle")
@MainActor
struct HandoffActivityManagerTests {

    @Test("Starting playback makes the Handoff activity current")
    func startingPlaybackMakesActivityCurrent() {
        let spy = SpyCurrentActivity()
        let manager = HandoffActivityManager(makeActivity: { spy })

        manager.setPlaybackState(isPlaying: true)

        #expect(spy.becomeCurrentCount == 1)
        #expect(spy.resignCurrentCount == 0)
    }

    @Test("Stopping playback after a play resigns the Handoff activity")
    func stoppingPlaybackAfterPlayResignsActivity() {
        let spy = SpyCurrentActivity()
        let manager = HandoffActivityManager(makeActivity: { spy })

        manager.setPlaybackState(isPlaying: true)
        manager.setPlaybackState(isPlaying: false)

        #expect(spy.becomeCurrentCount == 1)
        #expect(spy.resignCurrentCount == 1)
    }

    @Test("Repeated true calls make the activity current only once")
    func repeatedTrueCallsAreIdempotent() {
        let spy = SpyCurrentActivity()
        let manager = HandoffActivityManager(makeActivity: { spy })

        manager.setPlaybackState(isPlaying: true)
        manager.setPlaybackState(isPlaying: true)
        manager.setPlaybackState(isPlaying: true)

        #expect(spy.becomeCurrentCount == 1)
        #expect(spy.resignCurrentCount == 0)
    }

    @Test("A false call before any play is a no-op")
    func falseBeforeAnyPlayIsNoOp() {
        let spy = SpyCurrentActivity()
        let manager = HandoffActivityManager(makeActivity: { spy })

        manager.setPlaybackState(isPlaying: false)

        #expect(spy.becomeCurrentCount == 0)
        #expect(spy.resignCurrentCount == 0)
    }

    @Test("Repeated false calls after a play resign only once")
    func repeatedFalseCallsAfterPlayAreIdempotent() {
        let spy = SpyCurrentActivity()
        let manager = HandoffActivityManager(makeActivity: { spy })

        manager.setPlaybackState(isPlaying: true)
        manager.setPlaybackState(isPlaying: false)
        manager.setPlaybackState(isPlaying: false)

        #expect(spy.becomeCurrentCount == 1)
        #expect(spy.resignCurrentCount == 1)
    }

    @Test("makeDefaultActivity produces a Handoff-eligible play activity")
    func makeDefaultActivityIsHandoffEligible() {
        let activity = HandoffActivityManager.makeDefaultActivity()

        #expect(activity.activityType == WXYCUserActivity.play)
        #expect(activity.isEligibleForHandoff == true)
        #expect(activity.title?.contains(RadioStation.WXYC.name) == true)
        #expect(activity.userInfo?["origin"] as? String == "handoff")
    }
}

// MARK: - WXYCUserActivity Play Type Tests

@Suite("WXYCUserActivity play type")
struct WXYCUserActivityPlayTypeTests {

    @Test("play matches the NSUserActivityTypes entry the build expanded")
    func playMatchesDeclaredActivityType() throws {
        // WXYCTests is host-app-tested (TEST_HOST = WXYC.app), so Bundle.main
        // here resolves to the running WXYC app's bundle, not the test bundle.
        //
        // Comparing the constant against the *built* Info.plist is what gives
        // this test teeth. The obvious alternative — comparing it against a
        // locally recomputed "\(Bundle.main.bundleIdentifier).play" — cannot
        // fail in any configuration whose bundle id equals the literal the
        // constant used to hardcode, and that describes Debug TestFlight,
        // which is the configuration the test action actually builds. Reading
        // the declaration instead catches both halves of the real invariant:
        // that $(PRODUCT_BUNDLE_IDENTIFIER) expanded at build time rather than
        // shipping as a literal "$(...)" string, and that the Swift constant
        // has not drifted from what Info.plist declares. Either failure would
        // break Handoff and continuation silently.
        let declaredTypes = try #require(
            Bundle.main.object(forInfoDictionaryKey: "NSUserActivityTypes") as? [String]
        )

        #expect(declaredTypes.contains(WXYCUserActivity.play))
    }
}

// MARK: - WXYCUserActivity Continuation Reason Tests

@Suite("WXYCUserActivity continuation reason")
struct WXYCUserActivityContinuationReasonTests {

    @Test("A Handoff-originated play activity attributes .handoff")
    func handoffOriginAttributesHandoff() {
        let reason = WXYCUserActivity.continuationReason(
            activityType: WXYCUserActivity.play,
            userInfo: ["origin": "handoff"]
        )

        #expect(reason == .handoff)
    }

    @Test("A play activity with any other origin attributes .quickAction", arguments: [
        ["origin": "home screen quick action"],
        ["origin": "donateSiriIntent"],
    ] as [[String: String]])
    func nonHandoffOriginAttributesQuickAction(userInfo: [String: String]) {
        let reason = WXYCUserActivity.continuationReason(
            activityType: WXYCUserActivity.play,
            userInfo: userInfo
        )

        #expect(reason == .quickAction)
    }

    @Test("A play activity with nil userInfo attributes .quickAction")
    func nilUserInfoAttributesQuickAction() {
        let reason = WXYCUserActivity.continuationReason(
            activityType: WXYCUserActivity.play,
            userInfo: nil
        )

        #expect(reason == .quickAction)
    }

    @Test("A non-play activity type attributes nil")
    func nonPlayActivityTypeAttributesNil() {
        let reason = WXYCUserActivity.continuationReason(
            activityType: NSUserActivityTypeBrowsingWeb,
            userInfo: nil
        )

        #expect(reason == nil)
    }
}

// MARK: - Spy

/// Spy conforming to `CurrentActivityControlling` so tests can assert on the
/// Handoff activity lifecycle without touching the real `NSUserActivity`
/// Handoff machinery.
@MainActor
final class SpyCurrentActivity: CurrentActivityControlling {
    private(set) var becomeCurrentCount = 0
    private(set) var resignCurrentCount = 0

    func becomeCurrent() {
        becomeCurrentCount += 1
    }

    func resignCurrent() {
        resignCurrentCount += 1
    }
}
