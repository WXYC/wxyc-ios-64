//
//  PlaylistServiceEnvironmentTests.swift
//  AppServices
//
//  Proves the `\.playlistService` environment key's missed-injection path is
//  loud, not silent (WXYC/wxyc-ios-64#768). `PlaylistServiceEnvironmentDefault`
//  is the seam `PlaylistServiceKey.defaultValue` calls when nothing was
//  injected; a live `assertionFailure()` would trap the test process under
//  the debug configuration `swift test` runs in, so these tests exercise the
//  seam directly with an injected `assert` closure rather than reading the
//  real SwiftUI environment default.
//
//  Created by Jake Bromberg on 08/10/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Playlist
import Synchronization
import Testing
@testable import AppServices

@Suite("PlaylistService environment default")
struct PlaylistServiceEnvironmentTests {
    @Test("a missing injection fires the miss hook")
    func missingInjectionFiresMissHook() {
        // `assert` is `@Sendable` (it stands in for `assertionFailure`, called
        // from a `static var` getter), so the spy needs a thread-safe capture
        // rather than a plain `var`.
        let fired = Mutex(false)
        _ = PlaylistServiceEnvironmentDefault.missingInjectionFallback(assert: { fired.withLock { $0 = true } })
        #expect(fired.withLock { $0 })
    }

    @Test("a missing injection still returns a usable service, not nil")
    func missingInjectionReturnsUsableFallback() {
        // Compiles only because the fallback's return type is `PlaylistService`,
        // not `PlaylistService?` — the old `guard let playlistService else {
        // return }` call sites (StationView, WatchXYC's PlayerPage/PlaylistPage,
        // DebugPanel's VisualizerDebugView) no longer compile against this type
        // and were rewritten to read it unconditionally.
        let service: PlaylistService = PlaylistServiceEnvironmentDefault.missingInjectionFallback(assert: {})

        // A live, functioning stream — not a stub that traps on first use —
        // proves the fallback is safe to hand a view in Release, where
        // `assertionFailure` above is a no-op.
        _ = service.updates()
    }
}
