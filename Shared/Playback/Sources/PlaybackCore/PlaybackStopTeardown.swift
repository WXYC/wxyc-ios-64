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
