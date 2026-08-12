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
    /// Still a single `static let`, deliberately, rather than a computed
    /// `defaultValue`: SwiftUI reads `EnvironmentKey.defaultValue` afresh on
    /// every lookup that misses, so a computed default would allocate a new
    /// `PlaylistService` per read — each one kicking off its own cached-
    /// playlist load and, once a view subscribes to `updates()`, its own
    /// 30-second poll loop writing the app group's shared playlist cache key
    /// (the same key the widget reads). One shadow is a bug; one shadow per
    /// body evaluation is a resource leak.
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
