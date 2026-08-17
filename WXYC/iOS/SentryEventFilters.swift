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

    /// Stands in for the in-app function when the sampled stack has none.
    ///
    /// Named rather than empty so the bucket describes itself in the Sentry UI.
    /// This is not a degenerate case to engineer around: Sentry truncates a
    /// thread at 100 frames and keeps the leaf-most ones, so deep SwiftUI
    /// render recursion loses every app frame near the root. IOS-23 is exactly
    /// 100 frames of AttributeGraph → CoreText with no app frame anywhere.
    /// Those events really are one category — "render stall with no
    /// attributable app frame" — and collapsing them together is the point.
    nonisolated static let noInAppFrame = "no-app-frame"

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
            secondsSinceLaunch: event.timestamp?.timeIntervalSince(launchedAt),
            // The ANR integration hangs thread 0's stacktrace off the exception
            // itself, so this is the crashing thread's.
            innermostInAppFunction: innermostInAppFunction(in: exception?.stacktrace?.frames)
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
    /// - The in-app function is what keeps the first three from over-collapsing.
    ///   With non-fully-blocking hangs dropped, only `App Hang Fully Blocked`
    ///   and its `Fatal` counterpart can ever be created, so the first three
    ///   components alone have exactly three reachable values for the whole app
    ///   — a Metal stall, a playlist decode and an artwork decode would share
    ///   one issue, and resolving it after fixing one cause would re-open it as
    ///   a regression from an unrelated one.
    ///
    /// Measured against 30 days of real events before shipping this: ~97% of
    /// hang events carry at least one in-app frame and get a specific
    /// attribution, so the fallback is rare by volume even though it covers
    /// roughly a third of the *distinct* issues — all of them one- or two-event
    /// SwiftUI render stalls that genuinely belong together.
    ///
    /// - Parameters:
    ///   - mechanismType: `exceptions.first.mechanism.type`.
    ///   - exceptionType: `exceptions.first.type`.
    ///   - secondsSinceLaunch: Event timestamp minus this process's launch, or
    ///     `nil` when the event carries no timestamp.
    ///   - innermostInAppFunction: The deepest app frame's function name, or
    ///     `nil` when the sampled stack has none.
    /// - Returns: The fingerprint, or `nil` to leave grouping alone.
    nonisolated static func appHangFingerprint(
        mechanismType: String?,
        exceptionType: String?,
        secondsSinceLaunch: TimeInterval?,
        innermostInAppFunction: String?
    ) -> [String]? {
        guard mechanismType == appHangMechanismType else {
            return nil
        }

        return [
            "app-hang",
            exceptionType ?? "unknown",
            launchPhase(secondsSinceLaunch: secondsSinceLaunch),
            innermostInAppFunction ?? noInAppFrame,
        ]
    }

    /// The deepest frame belonging to this app, which is the most specific
    /// attribution the sampled stack offers.
    ///
    /// Sentry orders frames root-first and leaf-last —
    /// `SentryStacktraceBuilder` reverses them under the comment "The frames
    /// must be ordered from caller to callee, or oldest to youngest" — so the
    /// innermost app frame is the *last* one, not the first. That direction is
    /// the whole value of this: on the real IOS-4C event it picks
    /// `AudioEnginePlayer.play` over its caller
    /// `MP3Streamer.handleDecodedBuffer`. Reversing it would silently make
    /// every fingerprint coarser.
    ///
    /// The function name only — never the line number or instruction address,
    /// which would re-fragment the issue on every edit to an unrelated line in
    /// the same file. Frames with no symbol are skipped rather than allowed to
    /// win with an empty name, and an absent `inApp` reads as not-in-app.
    ///
    /// - Parameter frames: The crashing thread's frames, root-first.
    /// - Returns: The deepest named in-app function, or `nil` if there is none.
    nonisolated static func innermostInAppFunction(in frames: [Frame]?) -> String? {
        frames?.last { $0.inApp?.boolValue == true && $0.function?.isEmpty == false }?.function
    }

    /// Whether the hang happened during launch, later on, or at a time this
    /// process cannot speak to.
    ///
    /// Negative elapsed time is not a defensive check, and it is not an edge
    /// case either — for fatal hangs it is the *only* outcome. Under tracking
    /// V2 the SDK writes the hang event to disk when the hang starts and only
    /// sends it when the hang ends; if the watchdog kills the app first, the
    /// stored event is replayed on the next launch as a `Fatal` hang, still
    /// carrying the timestamp of the session that died. That replay happens in
    /// `captureStoredAppHangEvent`, called from the integration's `install`
    /// — i.e. inside `SentrySDK.start`, strictly before any hang of the current
    /// session could be stored. So a replayed event's timestamp is always from
    /// a dead session and always precedes this process's launch.
    ///
    /// The practical consequence, worth knowing before reading a dashboard:
    /// every `Fatal` hang is `unknown`, and no non-fatal hang ever is unless the
    /// event carries no timestamp at all. Splitting fatal hangs by phase would
    /// need the stored event's own session start, which is not on the event.
    /// `unknown` says what is actually known.
    nonisolated private static func launchPhase(secondsSinceLaunch: TimeInterval?) -> String {
        guard let secondsSinceLaunch, secondsSinceLaunch >= 0 else {
            return "unknown"
        }

        return secondsSinceLaunch < launchWindow ? "launch" : "runtime"
    }
}
