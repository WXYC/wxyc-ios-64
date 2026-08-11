//
//  PollUntil.swift
//  Playback
//
//  The one poll-until-deadline helper shared by every Playback test surface,
//  so timeout mechanics can't drift between copies.
//
//  Created by Jake Bromberg on 08/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// The bound every wait in the Playback test surface derives from.
///
/// CI run 31205214380 (#807) descheduled the xctest process for ~10.5s at a
/// time: timerless tests took ~10.5s alongside timed ones, output gaps ran
/// 38s/41s/68s, and Playback's waits — 5s at most call sites, 10s at two —
/// expired while the process was simply not running. 30s gives roughly 3x
/// headroom over that measurement
/// while staying under the same run's 49s worst-case test duration, so it is
/// bounded by observed data at both ends rather than picked for feel.
///
/// Single-sourced deliberately. This was three per-suite copies with
/// paraphrased derivations that had already drifted apart in detail, plus a
/// prose cross-reference from `MockAudioSession.deactivationHoldCap` that a
/// raise in any one copy would have silently invalidated.
public let stallTolerantTimeout: Duration = .seconds(30)

/// Polls `condition` on the main actor until it holds or `timeout` expires,
/// sleeping between checks so pending main-actor work — state-stream
/// observers, queued `Task { @MainActor … }` blocks, detached-task
/// continuations — can drain. Returns silently on timeout: pair it with an
/// `#expect` on the same condition so the failure is visible.
///
/// Sleeps rather than spinning on `Task.yield()`. Much of what this helper
/// waits on is itself main-actor work — timer loops, `@MainActor` tick
/// callbacks — and a yield spin on the same actor competes with the thing it
/// is waiting for over exactly the resource that thing needs to make
/// progress. A yield spin also cannot be cancelled by Swift Testing's
/// `.timeLimit`, so an unsatisfied wait pins the actor for the full timeout
/// instead of failing; sleeping suspends properly and stays cancellable.
/// (#807 restored this after a gate conversion replaced a sleeping suite-local
/// helper with the yield-spinning shared one and raised its bound 30x in the
/// same move.)
///
/// The deadline uses `ContinuousClock`, not `Date`: the wall clock can step
/// (NTP, DST, a manual change) mid-test, and this helper is load-bearing for
/// every deferred-handback assertion in the package.
///
/// Keep the cap. It is not a latency assertion — nothing reads the elapsed
/// time — it is the only thing standing between an unmet condition and a
/// simulator step that never terminates.
@MainActor
public func pollUntil(_ condition: @MainActor () -> Bool, timeout: Duration = stallTolerantTimeout) async {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !condition(), clock.now < deadline {
        do {
            try await Task.sleep(for: .milliseconds(1))
        } catch {
            // Cancelled. Returning is the point of sleeping rather than
            // yielding — swallowing this with `try?` would turn a cancelled
            // poll into the tight spin the sleep exists to avoid.
            return
        }
    }
}

/// Polls `sample` on the main actor until its value has stopped changing for
/// `dwell`, or `timeout` expires. Returns silently on timeout, same contract as
/// ``pollUntil``: pair it with an assertion on whatever the quiescence was
/// supposed to establish.
///
/// The quiescence counterpart to ``pollUntil``. Use it when what you are waiting
/// for is "some background pipeline has run dry" rather than a condition that
/// latches true. ``pollUntil`` cannot express that: there is no instant at which
/// "nothing more is coming" becomes observably true, so there is no predicate to
/// poll.
///
/// What it replaces is a fixed `Task.sleep`, picked long enough to cover the
/// pipeline on an unloaded machine. That is a silent failure mode under load —
/// the sleep elapses, the pipeline is still draining, and the test proceeds to
/// race whatever the leftover work does next. This waits as long as the machine
/// actually needs and is bounded only by the cap.
///
/// `dwell` must be comfortably longer than the gap between two consecutive items
/// the pipeline emits, or a scheduling hiccup part-way through a drain reads as
/// quiescence. The 250ms default is far above the sub-millisecond inter-buffer
/// gap of the MP3 decode path this was written for, while still costing less
/// than the 300ms blind sleep it replaced there.
@MainActor
public func pollUntilStable(
    dwell: Duration = .milliseconds(250),
    timeout: Duration = stallTolerantTimeout,
    _ sample: @MainActor () -> Int
) async {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    var lastValue = sample()
    var lastChange = clock.now

    while clock.now < deadline {
        do {
            try await Task.sleep(for: .milliseconds(5))
        } catch {
            // Cancelled — same reasoning as `pollUntil`: return rather than spin.
            return
        }
        let value = sample()
        if value != lastValue {
            lastValue = value
            lastChange = clock.now
        } else if clock.now - lastChange >= dwell {
            return
        }
    }
}
