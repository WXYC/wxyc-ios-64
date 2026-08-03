//
//  PendingHandleWave.swift
//  Playlist
//
//  Holds a one-shot on-air handle wave until it can actually be seen — the app
//  foregrounded and the handle on-screen. A DJ sign-on that lands while the app
//  is backgrounded, or while the playlist is scrolled past the banner, would
//  otherwise animate unseen and be wasted; instead the wave waits for the next
//  visible moment. Pure and view-free, so the defer/replay logic is unit-tested
//  without a host.
//
//  Created by Jake Bromberg on 08/03/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Gates a one-shot handle wave on whether it can currently be seen, deferring it
/// otherwise and replaying it the moment the handle becomes visible again.
///
/// The view feeds it two things: a *request* to wave (on launch or a DJ change),
/// and *gate changes* (the app foregrounding, or the handle scrolling into view).
/// Each call returns the start delay to play right now, or `nil` to play nothing —
/// so the view keeps the animation scheduling and this stays a pure decision.
public struct PendingHandleWave {
    /// The start delay of a wave awaiting a visible moment, or `nil` when nothing
    /// is waiting. A newer request overwrites it, so only the most recent missed
    /// wave replays — the handle catches up to the current DJ, it doesn't stutter
    /// through every change it slept through.
    public private(set) var deferredDelay: TimeInterval?

    public init() {}

    /// Requests a wave with the given start `delay`. When `canPlayNow` the wave
    /// should play immediately — returns `delay` and clears any deferral. Otherwise
    /// the wave is held (returns `nil`) until ``resume(canPlayNow:)`` reports the
    /// handle visible again.
    ///
    /// - Parameters:
    ///   - delay: How long the caller wants to wait before the wave starts once it
    ///     does play (e.g. the launch settle delay); carried through a deferral.
    ///   - canPlayNow: Whether the handle is currently visible and the app active.
    /// - Returns: `delay` to play now, or `nil` when the wave was deferred.
    public mutating func request(delay: TimeInterval, canPlayNow: Bool) -> TimeInterval? {
        if canPlayNow {
            deferredDelay = nil
            return delay
        }
        deferredDelay = delay
        return nil
    }

    /// Re-evaluates a deferred wave after the app foregrounds or the handle scrolls
    /// into view. Returns the delay to play now — clearing the deferral so it fires
    /// only once — when a wave was waiting and `canPlayNow`; otherwise `nil`.
    ///
    /// - Parameter canPlayNow: Whether the handle is now visible and the app active.
    /// - Returns: The deferred wave's delay to play now, or `nil` when nothing was
    ///   waiting or it still can't be seen.
    public mutating func resume(canPlayNow: Bool) -> TimeInterval? {
        guard canPlayNow, let delay = deferredDelay else { return nil }
        deferredDelay = nil
        return delay
    }
}
