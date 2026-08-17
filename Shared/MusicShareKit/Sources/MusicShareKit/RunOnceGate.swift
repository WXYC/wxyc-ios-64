//
//  RunOnceGate.swift
//  MusicShareKit
//
//  A closure gate that runs its body at most once per instance. Backs
//  MusicShareKit.configure(_:)'s once-per-process guard (#956): a caller
//  that runs on every presentation — the share extension's
//  ShareViewController.viewDidLoad — should install _authService only on
//  the first call in a process, so the in-memory AuthenticationService
//  (and its cachedSession) survives across presentations instead of being
//  rebuilt from scratch every time.
//
//  Created by Jake Bromberg on 08/17/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Synchronization

/// Runs a closure at most once per instance.
///
/// Thread-safe: `configure(_:)` is `public` and `nonisolated`, so nothing in
/// its signature confines callers to the main thread even though today's two
/// call sites (app launch, `ShareViewController.viewDidLoad`) both run there.
/// An unsynchronized check-then-set would let two concurrent callers both
/// pass the guard and both rebuild `_authService` — precisely the failure
/// this gate exists to prevent — so the flag lives in a `Mutex`, per
/// `docs/swift-style.md`'s preference for `Mutex`/`Atomic` over `NSLock`.
/// The lock is held across `body` so a losing caller blocks until the
/// winner's configuration is fully installed, rather than racing ahead and
/// observing half-built global state.
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
