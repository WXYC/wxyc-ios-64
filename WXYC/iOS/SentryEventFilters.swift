//
//  SentryEventFilters.swift
//  WXYC
//
//  The `beforeSend` hook for `WXYCApp.setUpSentry()`. Today it does one thing:
//  give app-hang events a stable fingerprint so the SDK's stack-signature
//  grouping stops shattering one problem into dozens of issues. It is also the
//  app's only `beforeSend`, so it is written to be the place every later filter
//  is added — see `beforeSend(_:launchedAt:)`.
//
//  Created by Jake Bromberg on 08/16/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Sentry

/// Event rewriting applied on the way out of the SDK.
///
/// Every member is `nonisolated` on purpose. This module builds with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so these would otherwise be
/// main-actor-isolated, and the SDK calls `beforeSend` on its own background
/// queue — the same reasoning spelled out at `WXYCApp.donateSiriIntent()`.
enum SentryEventFilters {

    /// How long after launch a hang still counts as a launch hang.
    ///
    /// Five seconds because every cold-launch stall examined in the 30-day
    /// sample landed within 5 s of app start, and nothing else clustered near
    /// the boundary — so the split is being read off a gap in the data rather
    /// than drawn through the middle of a cluster.
    nonisolated static let launchWindow: TimeInterval = 5

    /// The mechanism type the ANR integration stamps on every app-hang event
    /// (`SentryANRTrackingIntegration.m`). Matched exactly: it is a constant in
    /// the SDK, and a loose match would start regrouping unrelated events.
    nonisolated static let appHangMechanismType = "AppHang"

    /// The `beforeSend` body, and the place to add the next filter.
    ///
    /// Two rules hold for anything added here, because this runs on *every*
    /// event the SDK sends: it must be cheap, and it must return `event`
    /// unchanged for anything it does not recognise. Returning `nil` discards
    /// the event entirely, and a filter that throws or force-unwraps takes all
    /// error reporting down with it — silently, since there is no reporting
    /// left to report the failure.
    ///
    /// A new filter should be a `private static func` that takes the event,
    /// does nothing when the event is not its business, and is called from the
    /// sequence below. Deliberately no simulator or foreign-app filtering:
    /// `BuildEnvironment` already tags those in `options.environment`, so they
    /// can be excluded in the Sentry UI without throwing the data away.
    ///
    /// - Parameters:
    ///   - event: The event the SDK is about to send. Mutated in place.
    ///   - launchedAt: When this process configured Sentry — see
    ///     `WXYCApp.setUpSentry()` for why that stands in for launch.
    /// - Returns: The event to send, or `nil` to drop it. Never `nil` today.
    nonisolated static func beforeSend(_ event: Event, launchedAt: Date) -> Event? {
        applyAppHangFingerprint(to: event, launchedAt: launchedAt)

        return event
    }

    /// Groups app hangs by what kind of hang it was and whether it happened at
    /// launch, in place of the sampled stack.
    ///
    /// Stack-signature grouping is what fragments these: thread 0 runs past
    /// Sentry's 100-frame truncation cap, so app frames fall off the bottom and
    /// the culprit lands on whatever runtime internal the sampler caught —
    /// `GSFontCacheGetDictionary`, `SwiftHashTable::equal`. Over 30 days that
    /// turned 1207 hang events into 68 issues, 40 of them holding a single
    /// event. The sampled stack stays on the event; only the grouping changes.
    nonisolated private static func applyAppHangFingerprint(to event: Event, launchedAt: Date) {
        // `exceptions` is empty for message captures and transactions, so every
        // step here is optional. An event that is not an app hang falls out at
        // the mechanism check inside `appHangFingerprint` and keeps the SDK's
        // own grouping.
        let exception = event.exceptions?.first

        guard let fingerprint = appHangFingerprint(
            mechanismType: exception?.mechanism?.type,
            exceptionType: exception?.type,
            // Both sides are wall-clock: `timestamp` is stamped when the hang
            // was *detected*, not when it is sent, which is what makes the
            // fatal case below work.
            secondsSinceLaunch: event.timestamp?.timeIntervalSince(launchedAt)
        ) else {
            return
        }

        event.fingerprint = fingerprint
    }

    /// Builds the fingerprint for an app-hang event, or returns `nil` if the
    /// event is not an app hang.
    ///
    /// The scheme is `["app-hang", <hang type>, <phase>]`:
    ///
    /// - `"app-hang"` is a constant prefix, so hangs can never merge with
    ///   anything that is not a hang.
    /// - The hang type is the SDK's own exception type, carried verbatim rather
    ///   than mapped onto a local vocabulary. Under tracking V2 that is one of
    ///   `App Hang Fully Blocked`, `App Hang Non Fully Blocked` and their two
    ///   `Fatal` counterparts; V1 only ever produced `App Hanging`. Passing it
    ///   through means a type added by a future SDK gets its own group instead
    ///   of silently merging into a neighbour's, and the fingerprint reads the
    ///   same as the issue title in Sentry.
    /// - The phase is the actionable axis: a stall during first render is a
    ///   different engineering problem from one an hour into a session, and
    ///   nothing else on the event distinguishes them.
    ///
    /// - Parameters:
    ///   - mechanismType: `exceptions.first.mechanism.type`.
    ///   - exceptionType: `exceptions.first.type`.
    ///   - secondsSinceLaunch: Event timestamp minus this process's launch, or
    ///     `nil` when the event carries no timestamp.
    /// - Returns: The fingerprint, or `nil` to leave grouping alone.
    nonisolated static func appHangFingerprint(
        mechanismType: String?,
        exceptionType: String?,
        secondsSinceLaunch: TimeInterval?
    ) -> [String]? {
        guard mechanismType == appHangMechanismType else {
            return nil
        }

        return ["app-hang", exceptionType ?? "unknown", launchPhase(secondsSinceLaunch: secondsSinceLaunch)]
    }

    /// Whether the hang happened during launch, later on, or at a time this
    /// process cannot speak to.
    ///
    /// Negative elapsed time is not a defensive check, it is a real case with a
    /// real cause. Under tracking V2 the SDK writes the hang event to disk when
    /// the hang starts and only sends it when the hang *ends*; if the watchdog
    /// kills the app first, the stored event is replayed on the next launch as
    /// a `Fatal` hang, still carrying the timestamp of the session that died
    /// (`SentryANRTrackingIntegration.captureStoredAppHangEvent`). Measured
    /// against the new process's launch that is negative — often by hours — and
    /// calling it a launch hang would put the most severe class of hang in the
    /// wrong bucket. `unknown` says what is actually known.
    nonisolated private static func launchPhase(secondsSinceLaunch: TimeInterval?) -> String {
        guard let secondsSinceLaunch, secondsSinceLaunch >= 0 else {
            return "unknown"
        }

        return secondsSinceLaunch < launchWindow ? "launch" : "runtime"
    }
}
