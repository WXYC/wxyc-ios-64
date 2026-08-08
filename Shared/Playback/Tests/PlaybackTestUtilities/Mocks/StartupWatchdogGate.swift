//
//  StartupWatchdogGate.swift
//  Playback
//
//  Deterministic stand-in for the wall-clock sleep behind a startup watchdog's
//  deadline (`MP3Streamer.armStartupWatchdog()` and
//  `AudioPlayerController.armStartupWatchdog()`). A real watchdog races
//  scheduler latency: under parallel-simulator load, the deadline can expire
//  before an async signal the watchdog depends on (e.g. `isWaitingForConnectivity`)
//  has had a chance to propagate, manufacturing the very escalation the test is
//  trying to prove does NOT happen. This gate removes the wall clock from the
//  decision entirely — a watchdog armed against it does not fire until the test
//  explicitly releases it, so a test can first prove a precondition (the park
//  signal landed) and only then let the watchdog fire, with no timing window in
//  which the two can race. See issue #787.
//
//  Created by Jake Bromberg on 08/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Synchronization

/// A turnstile standing in for a watchdog deadline: each call to ``sleep(for:)``
/// suspends until a ``release()``, mirroring how a watchdog's `Task.sleep`
/// suspends until its deadline elapses — except the "deadline" is now a
/// test-driven event instead of real elapsed time. Consumers re-arm by calling
/// ``sleep(for:)`` again (a watchdog that defers and re-arms itself needs one
/// ``release()`` per arm).
///
/// Two properties make it a faithful stand-in rather than merely a convenient
/// one, and both are load-bearing for the watchdogs it gates:
///
/// - **Cancellation is honoured.** Both call sites cancel the prior arm before
///   installing a new one. A cancelled ``sleep(for:)`` throws `CancellationError`
///   and retires, exactly as `Task.sleep` does. A gate that ignored cancellation
///   would leave every superseded arm suspended, and a later ``release()`` would
///   resume one of *those* — whose own `Task.isCancelled` guard makes it a silent
///   no-op — while the live arm stayed parked. The test would believe it drove N
///   watchdog fires and have driven none.
/// - **Releases are banked, not dropped.** ``release()`` with nothing parked
///   pre-authorizes the next arm instead of vanishing, so a test never has to
///   order ``waitForArm(timeout:)`` ahead of every ``release()`` to stay correct.
///
/// Backed by a `Mutex` rather than actor isolation because the cancellation
/// handler runs on whatever executor cancels the arming task.
public final class StartupWatchdogGate: @unchecked Sendable {
    /// Thrown by ``waitForArm(timeout:)`` when no watchdog arms within the
    /// deadline. A watchdog that has stopped arming is precisely the regression
    /// this gate exists to surface, so it fails loudly rather than letting the
    /// test proceed to assert against a state it never reached.
    public struct ArmTimeout: Error, CustomStringConvertible {
        public let timeout: Duration

        public var description: String {
            "No watchdog armed against the StartupWatchdogGate within \(timeout)."
        }
    }

    private struct Arm {
        let id: UInt64
        let continuation: CheckedContinuation<Void, any Error>
    }

    private enum Resumption {
        case fire
        case cancelled
    }

    private struct State {
        var parked: [Arm] = []
        /// Arms cancelled in the window between being issued an id and reaching
        /// the continuation, which the parking side consumes so it throws
        /// instead of suspending on a deadline nobody will ever release.
        var cancelledBeforeParking: Set<UInt64> = []
        var nextArmID: UInt64 = 0
        var permits = 0
        var fireCount = 0
        var requestedDurations: [Duration] = []
    }

    private let state = Mutex(State())

    /// Test seam used only by `StartupWatchdogGateTests`. Invoked after an arm
    /// has been issued its id and before it reaches the critical section that
    /// records its duration and decides its disposition, receiving the number
    /// of durations recorded up to that instant.
    ///
    /// It exists because the atomicity of those two steps cannot be pinned by
    /// racing them. The window between the two lock acquisitions is
    /// sub-microsecond, so a polling observer samples it essentially never — a
    /// test written that way passes just as readily against the *non*-atomic
    /// version, which is precisely the vacuity #807 is about. Suspending an
    /// arm inside the window converts an unwinnable race into a direct
    /// observation.
    private let onArmIssued: (@Sendable (_ recordedDurationCount: Int) -> Void)?

    public init(onArmIssued: (@Sendable (_ recordedDurationCount: Int) -> Void)? = nil) {
        self.onArmIssued = onArmIssued
    }

    /// Suspends until the next ``release()``, or throws `CancellationError` if
    /// the arming task is cancelled.
    ///
    /// `duration` never affects when this returns — the gate's whole point is
    /// that real elapsed time no longer decides when a watchdog fires — but it
    /// is recorded in ``requestedDurations`` so a test can still pin the
    /// deadline arithmetic that produced it.
    public func sleep(for duration: Duration) async throws {
        let id = state.withLock { state -> UInt64 in
            state.nextArmID += 1
            return state.nextArmID
        }

        if let onArmIssued {
            onArmIssued(state.withLock { $0.requestedDurations.count })
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let resumption = state.withLock { state -> Resumption? in
                    // Recorded here, in the same critical section as the
                    // cancelled/fire/park decision below, not in the id-
                    // allocating section above. Two separate lock
                    // acquisitions are two separate windows to a concurrent
                    // observer even with no `await` between them — an OS
                    // thread can be preempted between releasing one lock and
                    // acquiring the next regardless of Swift-level suspension
                    // points — so a reader taking this lock to check
                    // `requestedDurations.count` must see it change exactly
                    // when the arm's disposition (parked, fired, or retired)
                    // also changes, or the count is not a trustworthy
                    // quiescence point. See #807.
                    state.requestedDurations.append(duration)
                    if state.cancelledBeforeParking.remove(id) != nil { return .cancelled }
                    if state.permits > 0 {
                        state.permits -= 1
                        state.fireCount += 1
                        return .fire
                    }
                    state.parked.append(Arm(id: id, continuation: continuation))
                    return nil
                }
                switch resumption {
                case .fire: continuation.resume()
                case .cancelled: continuation.resume(throwing: CancellationError())
                case nil: break
                }
            }
        } onCancel: {
            let continuation = state.withLock { state -> CheckedContinuation<Void, any Error>? in
                guard let index = state.parked.firstIndex(where: { $0.id == id }) else {
                    // Cancellation raced ahead of the park (or arrived after the
                    // arm was already resumed, in which case this entry is inert
                    // — ids are never reused).
                    state.cancelledBeforeParking.insert(id)
                    return nil
                }
                return state.parked.remove(at: index).continuation
            }
            continuation?.resume(throwing: CancellationError())
        }
    }

    /// How many watchdogs are currently suspended on this gate.
    public var pendingArmCount: Int {
        state.withLock { $0.parked.count }
    }

    /// Whether an armed watchdog is currently suspended on this gate.
    public var hasPendingArm: Bool { pendingArmCount > 0 }

    /// How many arms have actually been resumed by a ``release()`` — either
    /// directly, or by consuming a release banked before the arm arrived.
    ///
    /// This is the evidence that a watchdog *fired*, which no assertion about
    /// the events it did or did not emit can supply on its own: "deferred
    /// correctly" and "never fired at all" both leave the analytics mock empty.
    /// ``releaseAll()`` is deliberately excluded — it is a teardown drain whose
    /// resumed tasks are already cancelled.
    public var fireCount: Int {
        state.withLock { $0.fireCount }
    }

    /// Every `duration` passed to ``sleep(for:)``, in the order each arm's
    /// cancelled/fired/parked disposition was decided — not necessarily the
    /// order `sleep(for:)` was *called*, which two arms racing for the lock
    /// can reorder. For a single caller driving one arm at a time (by far
    /// the common case, and every existing use of this property) the two
    /// orders coincide. The gate ignores these when deciding *when* to fire,
    /// so this is what keeps the deadline arithmetic behind them (clamping,
    /// relative ordering between two layers' watchdogs) under test rather
    /// than merely configured.
    public var requestedDurations: [Duration] {
        state.withLock { $0.requestedDurations }
    }

    /// Suspends until a watchdog has armed against this gate, throwing
    /// ``ArmTimeout`` if none does within `timeout`.
    ///
    /// The wait is a logic-based one — it polls for an arm rather than sleeping
    /// a fixed span — and the deadline exists only so a watchdog that stops
    /// re-arming fails the test instead of hanging the test target. Nothing is
    /// racing it: a watchdog cannot fire while its gate is closed.
    @MainActor
    public func waitForArm(timeout: Duration = stallTolerantTimeout) async throws {
        await pollUntil({ self.hasPendingArm }, timeout: timeout)
        guard hasPendingArm else { throw ArmTimeout(timeout: timeout) }
    }

    /// Resumes the oldest still-suspended ``sleep(for:)`` call, i.e. lets
    /// exactly one armed watchdog "fire". With nothing parked, the release is
    /// banked and pre-authorizes the next arm, so a test is free of ordering
    /// constraints between a release and the arm it releases.
    public func release() {
        let continuation = state.withLock { state -> CheckedContinuation<Void, any Error>? in
            guard !state.parked.isEmpty else {
                state.permits += 1
                return nil
            }
            state.fireCount += 1
            return state.parked.removeFirst().continuation
        }
        continuation?.resume()
    }

    /// Resumes every currently-suspended ``sleep(for:)`` call and discards any
    /// banked releases. Intended for test teardown: a watchdog's final re-arm is
    /// often left un-released on purpose (the test stopped driving it once its
    /// assertions were made), so without this a `CheckedContinuation` would stay
    /// suspended past the test's lifetime. Safe to call after the owning
    /// player/controller has already been stopped — the resumed watchdog task's
    /// own cancellation check discards the result. Does not count toward
    /// ``fireCount``.
    public func releaseAll() {
        let parked = state.withLock { state -> [Arm] in
            let parked = state.parked
            state.parked.removeAll()
            state.cancelledBeforeParking.removeAll()
            state.permits = 0
            return parked
        }
        for arm in parked {
            arm.continuation.resume()
        }
    }
}
