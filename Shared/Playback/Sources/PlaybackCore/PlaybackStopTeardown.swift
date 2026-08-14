//
//  PlaybackStopTeardown.swift
//  PlaybackCore
//
//  Encodes the six-step stop teardown shared by every PlaybackController
//  implementation: cancel the in-flight reconnect, reset backoff, stop the
//  heartbeat, clear playback intent, and apply the sessionID-survival rule.
//  Extracted from AudioPlayerController and RadioPlayerController, whose
//  `stop(reason:)` bodies duplicated this sequence — and the comment below —
//  verbatim (#755).
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Stateless holder for the shared stop-teardown sequence. Each
/// `PlaybackController` keeps ownership of its own stored properties
/// (`sessionID`, `playbackIntended`, `wasPlayingBeforeRouteDisconnect`, the
/// reconnect task, the backoff timer, the heartbeat) and passes them in —
/// as `inout` for the value-type fields this mutates directly, and as
/// closures for the reference-type side effects it can't own itself.
public enum PlaybackStopTeardown {
    /// Runs the six-step teardown for a `stop(reason:)` call.
    ///
    /// - Parameters:
    ///   - reason: Why playback was stopped.
    ///   - cancelReconnect: Cancels any in-flight reconnect attempt.
    ///   - resetBackoff: Resets the exponential backoff timer.
    ///   - stopHeartbeat: Stops the `playback_heartbeat` cadence.
    ///   - playbackIntended: Cleared unconditionally — the caller no longer intends playback.
    ///   - wasPlayingBeforeRouteDisconnect: Cleared unless this stop is itself the route-disconnect stop.
    ///   - sessionID: Cleared unless the sessionID-survival rule below applies.
    public static func run(
        reason: PlaybackReason,
        cancelReconnect: () -> Void,
        resetBackoff: () -> Void,
        stopHeartbeat: () -> Void,
        playbackIntended: inout Bool,
        wasPlayingBeforeRouteDisconnect: inout Bool,
        sessionID: inout String?
    ) {
        cancelReconnect()
        resetBackoff()
        stopHeartbeat()

        playbackIntended = false
        retireAutoResumeState(
            reason: reason,
            wasPlayingBeforeRouteDisconnect: &wasPlayingBeforeRouteDisconnect,
            sessionID: &sessionID
        )
    }

    /// The auto-resume-survival half of `run(…)`, callable on its own.
    ///
    /// Split out for `AudioPlayerController`'s idempotency guard (#933), which
    /// short-circuits the rest of the teardown for a stop that has nothing left
    /// to tear down. That guard's short-circuit is reached in exactly the state
    /// a route disconnect or an interruption leaves behind — no standing intent,
    /// idle player — so if the survival state were not retired here it could
    /// never be retired at all: the flag would outlive the listen and the next
    /// route reconnect would start audio with no user action. This is the one
    /// rule for both paths rather than a second copy on the guard, because two
    /// rules over the same two fields drift.
    ///
    /// Why the reason is a sufficient discriminator: the duplicate-dispatch bug
    /// behind #933 (#932) redelivers *the same command*, so a stray stop always
    /// arrives under the same reason as the stop it echoes — and the rule below
    /// already preserves precisely for the reasons that set the state. An echo
    /// of a route-disconnect stop therefore preserves; a Lock Screen pause on
    /// top of one does not, because it is a new listener decision rather than a
    /// repeat. Repeats of a non-survival reason stay harmless by being
    /// idempotent: the first already cleared both fields.
    ///
    /// - Parameters:
    ///   - reason: Why playback was stopped.
    ///   - wasPlayingBeforeRouteDisconnect: Cleared unless this stop is itself the route-disconnect stop.
    ///   - sessionID: Cleared unless the sessionID-survival rule below applies.
    public static func retireAutoResumeState(
        reason: PlaybackReason,
        wasPlayingBeforeRouteDisconnect: inout Bool,
        sessionID: inout String?
    ) {
        if reason != .routeDisconnected {
            wasPlayingBeforeRouteDisconnect = false
        }
        // Interruption/route-disconnect stops are an implementation detail of
        // "pause, then auto-resume" — the listen itself isn't over, so the
        // session id must survive them. Any other reason is a genuine end of
        // the listen; the next `play()` mints a fresh id. See #665.
        if reason != .interruptionBegan && reason != .routeDisconnected {
            sessionID = nil
        }
    }
}
