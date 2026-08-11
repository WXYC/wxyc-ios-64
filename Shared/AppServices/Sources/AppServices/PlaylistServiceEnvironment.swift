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
/// log, or test failure (WXYC/wxyc-ios-64#768). Every remaining consumer of
/// this key (StationView, WatchXYC's PlayerPage/PlaylistPage, DebugPanel's
/// VisualizerDebugView — everything without a `Singletonia` to fold the read
/// into instead) now gets a real, non-optional value and can no longer skip
/// past a miss with `guard let` or `?.`.
enum PlaylistServiceEnvironmentDefault {
    /// Resolves the fallback. `assert` traps in DEBUG (the default:
    /// `assertionFailure`, loud the moment a missed injection is first read)
    /// and is a no-op once Release strips assertions — so this always
    /// returns a real, disconnected-but-functional `PlaylistService` rather
    /// than `nil`. `assert` is overridable so tests can observe the miss
    /// path without crashing the test process: a live `assertionFailure()`
    /// traps under the debug configuration `swift test` runs in.
    static func missingInjectionFallback(assert: @Sendable () -> Void = defaultAssert) -> PlaylistService {
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
    static var defaultValue: PlaylistService {
        PlaylistServiceEnvironmentDefault.missingInjectionFallback()
    }
}

// MARK: - Environment Values Extension

public extension EnvironmentValues {
    var playlistService: PlaylistService {
        get { self[PlaylistServiceKey.self] }
        set { self[PlaylistServiceKey.self] = newValue }
    }
}
