//
//  PlaylistServiceEnvironment.swift
//  AppServices
//
//  SwiftUI Environment support for PlaylistService
//
//  Created by Jake Bromberg on 11/22/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Playlist

// MARK: - Missing-injection fallback

/// What `\.playlistService` resolves to when nothing was injected — a missed
/// `.environment(\.playlistService, ...)` call. Non-optional on purpose: a
/// silent `nil` is what let `PlaylistView`'s `.task` do `guard let
/// playlistService else { return }` and render forever-empty with no crash,
/// log, or test failure (WXYC/wxyc-ios-64#768). The type is the whole guard:
/// because `defaultValue` is non-optional, the `guard let` / `?.` call sites
/// that used to swallow a miss no longer compile, and every remaining
/// consumer of this key (WatchXYC's PlayerPage/PlaylistPage, DebugPanel's
/// VisualizerDebugView) gets a real, functioning value.
enum PlaylistServiceEnvironmentDefault {
    /// The single instance `\.playlistService` ever hands out on a miss.
    ///
    /// Built **silently**, with no assertion and no log. An earlier revision
    /// ran `assertionFailure` from this initializer on the theory that a
    /// correctly-injecting build would never construct it — but SwiftUI's own
    /// environment machinery evaluates `EnvironmentKey.defaultValue` while
    /// *processing* an `.environment(\.playlistService, ...)` write
    /// (`ChildEnvironment.updateValue()` reads the parent scope's slot
    /// through the key-path getter before storing the new value), so the
    /// initializer runs on every launch that injects correctly. Construction
    /// is not evidence of a miss, and the assertion crashed every Debug
    /// launch at startup — which also killed every simulator test run, since
    /// the app is the WXYCTests host ("the test runner hung before
    /// establishing connection").
    ///
    /// Cheaper since WXYC/wxyc-ios-64#964, but not free. `PlaylistService.init`
    /// no longer starts a cache-load `Task`, so building this shadow reads no
    /// disk cache and decodes no `Playlist`; loading, fetching, and polling all
    /// begin on first *use* (`waitForCacheLoad()` or `updates()`), which
    /// nothing on this path ever calls, so the shadow sits inert once built.
    /// It still builds a `PlaylistFetcher`, which constructs a data source and
    /// touches the shared error-reporting and analytics singletons through its
    /// default arguments. (The `UserDefaults.wxyc` read and PostHog flag lookup
    /// that used to happen here went with the v1 path — #262.) Making the rest
    /// lazy is a further step nobody has taken.
    ///
    /// Still a single `static let`, deliberately, and the `@Entry` default
    /// below *references* it rather than constructing one: `@Entry` emits a
    /// computed `defaultValue`, which SwiftUI reads afresh on every lookup that
    /// misses, so an inlined `PlaylistService()` would allocate a new
    /// `PlaylistService` per read — and per read that a caller actually
    /// subscribes to (`updates()`), its own cache load, fetch, and 30-second
    /// poll loop writing the app group's shared playlist cache key (the same
    /// key the widget reads). One inert shadow is a wasted allocation; one
    /// active shadow per body evaluation is a resource leak and a data
    /// hazard.
    static let shared = PlaylistService()
}

// MARK: - Environment Values Extension

public extension EnvironmentValues {
    /// The playlist service views read. Defaults to
    /// ``PlaylistServiceEnvironmentDefault/shared`` — a *reference*, never a
    /// construction; that constant's doc carries the two incidents that rule
    /// comes from.
    @Entry var playlistService: PlaylistService = PlaylistServiceEnvironmentDefault.shared
}
