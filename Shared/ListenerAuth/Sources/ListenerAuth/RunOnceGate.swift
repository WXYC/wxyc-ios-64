//
//  RunOnceGate.swift
//  ListenerAuth
//
//  A closure gate that runs its body at most once per instance (#956).
//
//  Created by Jake Bromberg on 08/17/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Synchronization

/// Runs a closure at most once per instance.
///
/// Thread-safe: nothing in `runOnce`'s signature confines callers to a single
/// thread or actor, so an unsynchronized check-then-set would let two
/// concurrent callers both pass the guard and both run the body — precisely
/// the failure this gate exists to prevent. The flag therefore lives in a
/// `Mutex`, per `docs/swift-style.md`'s preference for `Mutex`/`Atomic` over
/// `NSLock`. The lock is held across `body` so a losing caller blocks until
/// the winner's work is fully done, rather than racing ahead and observing
/// half-built state.
final class RunOnceGate: Sendable {
    private let state = Mutex(false)

    /// Whether `runOnce` has already consumed this gate.
    ///
    /// A test seam: it lets a suite assert its gate is still fresh, so a
    /// once-per-process assertion fails loudly instead of passing vacuously
    /// when something tripped the gate first.
    var hasRun: Bool {
        state.withLock { $0 }
    }

    /// Runs `body` the first time this is called; every subsequent call is
    /// a no-op.
    func runOnce(_ body: () -> Void) {
        state.withLock { hasRun in
            guard !hasRun else { return }
            hasRun = true
            body()
        }
    }
}
