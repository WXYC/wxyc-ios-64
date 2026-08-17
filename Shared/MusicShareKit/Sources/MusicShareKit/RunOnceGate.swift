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

/// Runs a closure at most once per instance.
///
/// Not thread-safe by design: every call site in this module runs on the
/// main thread (app launch, `ShareViewController.viewDidLoad`), matching
/// the rest of `MusicShareKit`'s `nonisolated(unsafe)` global state, which
/// carries the same single-threaded assumption. `@unchecked Sendable` so it
/// can back a `nonisolated(unsafe)` static, same as `_configuration` /
/// `_authService` above.
final class RunOnceGate: @unchecked Sendable {
    private var hasRun = false

    /// Runs `body` the first time this is called; every subsequent call is
    /// a no-op.
    func runOnce(_ body: () -> Void) {
        guard !hasRun else { return }
        hasRun = true
        body()
    }
}
