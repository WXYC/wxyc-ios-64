//
//  PlaylistServiceEnvironmentTests.swift
//  AppServices
//
//  Guards the `\.playlistService` environment key's two load-bearing
//  properties (WXYC/wxyc-ios-64#768): an injected service is the one that
//  resolves, and an uninjected read hands out one shared, functioning
//  fallback — silently.
//
//  Silently is the part with history: an earlier revision ran
//  `assertionFailure` from the fallback's initializer, assuming SwiftUI only
//  evaluates `EnvironmentKey.defaultValue` on a genuine miss. It doesn't —
//  `ChildEnvironment.updateValue()` evaluates it while processing the
//  `.environment(\.playlistService, ...)` write itself — so every Debug
//  launch crashed at startup. `uninjectedReadResolvesToSharedFallback` below
//  reads `defaultValue` end-to-end under the debug configuration `swift
//  test` runs in, which is exactly the read that used to trap; it is this
//  file's regression test for that crash. What keeps a missed injection loud
//  is the type alone: `defaultValue` is non-optional, so the `guard let` /
//  `?.` call sites that used to swallow a miss no longer compile.
//
//  Created by Jake Bromberg on 08/10/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Playlist
import SwiftUI
import Testing
@testable import AppServices

@Suite("PlaylistService environment default")
struct PlaylistServiceEnvironmentTests {
    @Test("an injected service is the one the key resolves to")
    func injectedServiceIsWhatResolves() {
        // Guards the getter/setter pair against addressing different keys —
        // which would silently route every consumer to the fallback.
        let injected = PlaylistService()
        var values = EnvironmentValues()
        values.playlistService = injected

        #expect(values.playlistService === injected)
    }

    @Test("an uninjected read resolves to one shared fallback, without trapping")
    func uninjectedReadResolvesToSharedFallback() {
        // This read evaluates `PlaylistServiceKey.defaultValue` for real — the
        // path that used to run `assertionFailure` and crash every Debug
        // launch. Surviving the read is half the test; the identity check is
        // the other half: two misses must hand back the *same* instance, or
        // each miss would spin up its own cached-playlist load and 30-second
        // poll loop against the app group's shared cache key.
        let first = EnvironmentValues().playlistService
        let second = EnvironmentValues().playlistService

        #expect(first === second)
    }

    @Test("the fallback is a usable service, not a stub that traps on first use")
    func fallbackIsUsable() {
        // A live, functioning stream proves the fallback is safe to hand a
        // view on a real miss — right content from a disconnected instance
        // beats a crash or a forever-empty screen.
        let service = EnvironmentValues().playlistService
        _ = service.updates()
    }
}
