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
import Logger
import Playlist

// MARK: - Missing-injection fallback

/// What `\.playlistService` resolves to when nothing was injected — a missed
/// `.environment(\.playlistService, ...)` call. Non-optional on purpose: a
/// silent `nil` is what let `PlaylistView`'s `.task` do `guard let
/// playlistService else { return }` and render forever-empty with no crash,
/// log, or test failure (WXYC/wxyc-ios-64#768). Every remaining consumer of
/// this key (WatchXYC's PlayerPage/PlaylistPage, DebugPanel's
/// VisualizerDebugView — everything without a `Singletonia` to fold the read
/// into instead) now gets a real, non-optional value and can no longer skip
/// past a miss with `guard let` or `?.`.
enum PlaylistServiceEnvironmentDefault {
    /// The single instance the key ever hands out on a miss — see
    /// ``PlaylistServiceKey``. A `static let`, deliberately, rather than
    /// building one inside a computed `defaultValue`: SwiftUI reads
    /// `EnvironmentKey.defaultValue` afresh on *every* environment lookup
    /// that misses, so a computed default would allocate a new
    /// `PlaylistService` per read — each one kicking off its own cached-
    /// playlist load and, once a view subscribes to `updates()`, its own
    /// 30-second poll loop writing the app group's shared playlist cache key
    /// (the same key the widget reads). One shadow is a bug; one shadow per
    /// body evaluation is a resource leak. Lazily initialized, so a build
    /// that injects correctly never constructs it at all.
    static let shared = missingInjectionFallback()

    /// Resolves the fallback. `assert` traps in DEBUG (the default:
    /// `assertionFailure`, loud the moment a missed injection is first read)
    /// and is a no-op once Release strips assertions — so this always
    /// returns a real, disconnected-but-functional `PlaylistService` rather
    /// than `nil`. `assert` is overridable so tests can observe the miss
    /// path without crashing the test process: a live `assertionFailure()`
    /// traps under the debug configuration `swift test` runs in.
    static func missingInjectionFallback(assert: @Sendable () -> Void = defaultAssert) -> PlaylistService {
        // Logged outside the `assert` hook, so the miss leaves evidence in a
        // shipping build too. Without this, Release strips the assertion and
        // the app silently runs on a service disconnected from the one
        // `Singletonia` owns — right content, wrong instance, no signal.
        Log(
            .error,
            category: .general,
            "PlaylistService missing from the environment; falling back to a disconnected instance. "
            + "Inject one via `.environment(\\.playlistService, ...)` before this view renders."
        )
        assert()
        return PlaylistService()
    }

    private static let defaultAssert: @Sendable () -> Void = {
        assertionFailure(
            "PlaylistService missing from the environment — inject one via " +
            "`.environment(\\.playlistService, ...)` before this view renders."
        )
    }
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
