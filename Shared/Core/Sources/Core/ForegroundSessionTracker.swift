//
//  ForegroundSessionTracker.swift
//  Core
//
//  Collapses a run of ``ForegroundVisibility`` transitions into one measured
//  on-screen span — how long the app was actually in front of the listener,
//  which no analytics surface recorded before. Lives beside
//  ``ForegroundVisibility`` because it is that classification's only stateful
//  consumer, and in Core because the classification is here.
//
//  Created by Jake Bromberg on 08/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

/// Measures how long the app spends on screen, one visit at a time.
///
/// Feed it every ``ForegroundVisibility`` the app classifies, in order. It
/// returns a duration exactly once per completed visit — on the transition
/// that ends one — and `nil` for every other transition, so the caller can
/// report a session without tracking any state of its own.
///
/// Two properties are the reason this is a type rather than a pair of
/// timestamps at the call site:
///
/// - **`.noChange` is inert.** It is what a Control Center pull, a call
///   banner, or the app switcher looks like, and the app is still on screen
///   throughout. Closing the span there would truncate the real visit and open
///   a phantom second one; see ``ForegroundVisibility`` for why `.inactive`
///   cannot be read as an exit.
/// - **A repeated `.onScreen` is not a new visit.** The dismissed interruption
///   above arrives as on-screen → no-change → on-screen, and restarting the
///   clock on that second edge would report the tail of a visit as the whole
///   of it.
///
/// The span is measured on the monotonic `ContinuousClock`, the same reason
/// ``Timer`` is: a wall-clock adjustment mid-visit can otherwise make a
/// reported duration jump or go negative, and one negative sample is
/// meaningless in a distribution. `ContinuousClock` also keeps counting while
/// the device is asleep, which is correct here — the visit ends at the
/// transition, not at the moment the screen dimmed.
///
/// A visit that never happened reports nothing: a launch straight into the
/// background (a background refresh, a widget timeline reload) ends with an
/// off-screen transition that was never preceded by an on-screen one, and
/// reporting a zero for it would drag every distribution down.
///
/// A visit the app never leaves — because it was terminated, or crashed — is
/// never reported. The measurement is therefore a floor on time spent on
/// screen, not an exact total.
public struct ForegroundSessionTracker: Sendable {

    /// When the current visit began, or `nil` when the app is not on screen.
    private var startedAt: ContinuousClock.Instant?

    /// Creates a tracker with no visit in progress.
    public init() {}

    /// Records one visibility transition and reports the visit it completed.
    ///
    /// - Parameters:
    ///   - visibility: What the phase being entered says about visibility.
    ///   - instant: When the transition happened. Defaults to now; tests pass
    ///     explicit instants so no assertion depends on wall-clock timing.
    /// - Returns: The duration the app spent on screen, if this transition
    ///   ended a visit. `nil` otherwise.
    public mutating func record(
        _ visibility: ForegroundVisibility,
        at instant: ContinuousClock.Instant = ContinuousClock.now
    ) -> Duration? {
        switch visibility {
        case .onScreen:
            // Deliberately does not overwrite an existing start — see the type
            // doc on why a second on-screen edge is not a second visit.
            if startedAt == nil {
                startedAt = instant
            }
            return nil

        case .offScreen:
            guard let startedAt else { return nil }
            self.startedAt = nil
            return startedAt.duration(to: instant)

        case .noChange:
            return nil
        }
    }
}
