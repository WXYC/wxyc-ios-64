//
//  SentryEventFiltersTests.swift
//  WXYC
//
//  Pins the `beforeSend` app-hang fingerprint: which events it claims, the
//  fingerprint it builds for each of the SDK's five hang types, the launch/
//  runtime boundary, and — most of all — that it returns everything it does not
//  recognise untouched. `beforeSend` sees every event the SDK sends, so a
//  mistake here silently destroys error reporting rather than failing loudly.
//
//  Created by Jake Bromberg on 08/16/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Sentry
import Testing
@testable import WXYC

@Suite("Sentry event filters")
struct SentryEventFiltersTests {

    // MARK: - What the filter claims

    /// Anything that is not an app hang has to come back with no fingerprint at
    /// all, so the SDK's own grouping still applies. The lowercase near-miss
    /// pins the match as exact: the ANR integration writes precisely `AppHang`
    /// (`SentryANRTrackingIntegration.m:143`), and a filter that matched loosely
    /// would start regrouping unrelated events.
    @Test("An event without the AppHang mechanism is not claimed", arguments: nonHangMechanismTypes)
    func nonHangEventsAreNotClaimed(mechanismType: String?) {
        let fingerprint = SentryEventFilters.appHangFingerprint(
            mechanismType: mechanismType,
            exceptionType: "NSRangeException",
            secondsSinceLaunch: 1
        )

        #expect(fingerprint == nil)
    }

    // MARK: - Hang types

    /// The hang type is carried through verbatim rather than mapped, so a hang
    /// type added by a future SDK gets its own group instead of silently
    /// merging into a neighbour's.
    @Test("Each SDK hang type is carried into the fingerprint", arguments: sdkHangTypes)
    func hangTypeIsCarriedThrough(exceptionType: String) {
        let fingerprint = SentryEventFilters.appHangFingerprint(
            mechanismType: "AppHang",
            exceptionType: exceptionType,
            secondsSinceLaunch: 1
        )

        #expect(fingerprint == ["app-hang", exceptionType, "launch"])
    }

    /// The whole point of the change: fragmentation must not come back through
    /// the fingerprint itself. Five types across two phases is the ceiling, and
    /// each combination has to be its own slot — no collisions, no over-merging.
    @Test("The SDK's hang types never collide with each other")
    func hangTypesDoNotCollide() {
        let fingerprints = sdkHangTypes.flatMap { exceptionType in
            [1.0, 60.0].compactMap { seconds in
                SentryEventFilters.appHangFingerprint(
                    mechanismType: "AppHang",
                    exceptionType: exceptionType,
                    secondsSinceLaunch: seconds
                )
            }
        }

        #expect(fingerprints.count == 10)
        #expect(Set(fingerprints).count == 10)
    }

    @Test("A hang with no exception type still groups, under a named placeholder")
    func missingExceptionTypeGetsAPlaceholder() {
        let fingerprint = SentryEventFilters.appHangFingerprint(
            mechanismType: "AppHang",
            exceptionType: nil,
            secondsSinceLaunch: 1
        )

        #expect(fingerprint == ["app-hang", "unknown", "launch"])
    }

    // MARK: - Launch vs runtime

    @Test("Elapsed time since launch picks the phase", arguments: launchPhaseCases)
    func elapsedTimePicksThePhase(secondsSinceLaunch: TimeInterval?, expectedPhase: String) {
        let fingerprint = SentryEventFilters.appHangFingerprint(
            mechanismType: "AppHang",
            exceptionType: "App Hang Fully Blocked",
            secondsSinceLaunch: secondsSinceLaunch
        )

        #expect(fingerprint == ["app-hang", "App Hang Fully Blocked", expectedPhase])
    }

    // MARK: - Wiring, on real events

    /// The nil-safety case. `beforeSend` runs on every event the SDK sends, and
    /// an event with no exceptions at all is ordinary — a message capture, a
    /// transaction. It has to come back untouched, and above all it must not
    /// crash: a throwing `beforeSend` takes all error reporting down with it.
    @Test("An event with no exceptions is returned unchanged")
    func eventWithoutExceptionsIsReturnedUnchanged() {
        let event = Event()

        let result = SentryEventFilters.beforeSend(event, launchedAt: Date())

        #expect(result === event)
        #expect(event.fingerprint == nil)
    }

    /// End to end over the real object graph: this is the only coverage of the
    /// `exceptions?.first?.mechanism?.type` walk, which is where a nil-handling
    /// mistake would actually live.
    @Test("A real app-hang event comes back fingerprinted")
    func realHangEventIsFingerprinted() {
        let launchedAt = Date()
        let event = Event()
        let exception = Exception(value: "App hanging for at least 2000 ms.", type: "App Hang Fully Blocked")
        exception.mechanism = Mechanism(type: "AppHang")
        event.exceptions = [exception]
        event.timestamp = launchedAt.addingTimeInterval(1.5)

        let result = SentryEventFilters.beforeSend(event, launchedAt: launchedAt)

        #expect(result === event)
        #expect(event.fingerprint == ["app-hang", "App Hang Fully Blocked", "launch"])
    }

    /// A fatal hang is written to disk while the app is hanging and sent on the
    /// *next* launch (`SentryANRTrackingIntegration.captureStoredAppHangEvent`),
    /// carrying the timestamp of the session that died. Measured against this
    /// process's launch that elapsed time is negative, and the phase has to
    /// admit it does not know rather than calling a three-hour-old hang a
    /// launch hang.
    @Test("A fatal hang replayed on the next launch is not called a launch hang")
    func replayedFatalHangIsNotALaunchHang() {
        let launchedAt = Date()
        let event = Event()
        let exception = Exception(value: "App hanging.", type: "Fatal App Hang Fully Blocked")
        exception.mechanism = Mechanism(type: "AppHang")
        event.exceptions = [exception]
        event.timestamp = launchedAt.addingTimeInterval(-3600)

        _ = SentryEventFilters.beforeSend(event, launchedAt: launchedAt)

        #expect(event.fingerprint == ["app-hang", "Fatal App Hang Fully Blocked", "unknown"])
    }

    /// A non-hang event must survive the pipeline with its grouping untouched,
    /// verified on a real event rather than only through the pure function.
    @Test("A non-hang event keeps the SDK's own grouping")
    func nonHangEventKeepsDefaultGrouping() {
        let event = Event()
        let exception = Exception(value: "boom", type: "NSRangeException")
        exception.mechanism = Mechanism(type: "NSException")
        event.exceptions = [exception]

        let result = SentryEventFilters.beforeSend(event, launchedAt: Date())

        #expect(result === event)
        #expect(event.fingerprint == nil)
    }
}

// MARK: - Fixtures

/// Mechanism types that are not app hangs, including `nil` for an event with no
/// exceptions and a lowercase near-miss.
nonisolated let nonHangMechanismTypes: [String?] = [
    nil,
    "NSException",
    "signal",
    "mach",
    "apphang",
    "AppHangV2",
]

/// Every exception type `SentryAppHangTypeMapper` can produce, verified against
/// `SentryANRType.swift` in the pinned sentry-cocoa 8.58.4. The two `Fatal`
/// variants only exist once app-hang tracking V2 is enabled.
nonisolated let sdkHangTypes: [String] = [
    "App Hanging",
    "App Hang Fully Blocked",
    "App Hang Non Fully Blocked",
    "Fatal App Hang Fully Blocked",
    "Fatal App Hang Non Fully Blocked",
]

/// The launch/runtime boundary, pinned on both sides. `nil` is an event with no
/// timestamp; a negative value is a fatal hang replayed from an earlier session.
nonisolated let launchPhaseCases: [(secondsSinceLaunch: TimeInterval?, expectedPhase: String)] = [
    (nil, "unknown"),
    (-3600, "unknown"),
    (-0.001, "unknown"),
    (0, "launch"),
    (2.5, "launch"),
    (4.999, "launch"),
    (5, "runtime"),
    (5.001, "runtime"),
    (3600, "runtime"),
]
