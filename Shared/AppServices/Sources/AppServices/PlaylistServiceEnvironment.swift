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
    /// The single instance the key ever hands out — see ``PlaylistServiceKey``.
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
    /// Cheaper now, for a second reason on top of that one
    /// (WXYC/wxyc-ios-64#964): `PlaylistService.init` no longer starts a
    /// cache-load `Task`, so building this shadow no longer reads the disk
    /// cache or decodes a `Playlist`. Cache loading, fetching, and polling all
    /// begin on first *use* (`waitForCacheLoad()` or `updates()`), and nothing
    /// on this path ever calls either, so the shadow this default builds on
    /// every correctly-injecting launch sits inert once constructed.
    ///
    /// Constructing it is not free, though, and this comment previously
    /// claimed it was. Because no `apiVersion` is passed, `init` still
    /// resolves `PlaylistAPIVersion.loadActive()` — a `UserDefaults.wxyc` read
    /// plus a PostHog flag lookup — and still builds a
    /// `PlaylistFetcher(apiVersion:)`, which constructs a data source and
    /// touches the shared error-reporting and analytics singletons through its
    /// default arguments. Making *those* lazy too is a further step nobody has
    /// taken; don't read this as "the shadow is already free."
    ///
    /// Still a single `static let`, deliberately, rather than a computed
    /// `defaultValue`: SwiftUI reads `EnvironmentKey.defaultValue` afresh on
    /// every lookup that misses, so a computed default would allocate a new
    /// `PlaylistService` per read — and per read that a caller actually
    /// subscribes to (`updates()`), its own cache load, fetch, and 30-second
    /// poll loop writing the app group's shared playlist cache key (the same
    /// key the widget reads). One inert shadow is a wasted allocation; one
    /// active shadow per body evaluation is a resource leak and a data
    /// hazard.
    static let shared = PlaylistService()
}

// MARK: - Environment Key

private struct PlaylistServiceKey: EnvironmentKey {
    static let defaultValue: PlaylistService = PlaylistServiceEnvironmentDefault.shared
}

// MARK: - Environment Values Extension

public extension EnvironmentValues {
    var playlistService: PlaylistService {
        get { self[PlaylistServiceKey.self] }
        set { self[PlaylistServiceKey.self] = newValue }
    }
}
