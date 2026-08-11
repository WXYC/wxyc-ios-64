//
//  PlaylistAPIVersion.swift
//  Playlist
//
//  Controls which playlist API version to use via PostHog feature flag.
//
//  Created by Jake Bromberg on 01/01/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Analytics
import Caching

// MARK: - PlaylistAPIVersion

/// Available playlist API versions.
public enum PlaylistAPIVersion: String, CaseIterable, Identifiable, Hashable, Sendable {
    case v1 = "v1"
    case v2 = "v2"

    // MARK: - Persistence

    /// Uses app group UserDefaults so widget/intents can read the selected version
    private static var defaults: UserDefaults { .wxyc }
    private static let userDefaultsKey = "debug.selectedPlaylistAPIVersion"
    private static let manualSelectionKey = "debug.isPlaylistAPIManuallySelected"

    /// PostHog feature flag key
    static let featureFlagKey = "playlist_api_version"

    /// The API version a build falls back to when nothing overrides it.
    ///
    /// This constant is the app-version gate for the v2 rollout, and it is
    /// deliberately a compile-time constant rather than a remote lookup.
    ///
    /// `v3.1` reads this same flag on its production path but predates the v2
    /// envelope decode fix (`8b05e66e`, 2026-04-17): the v2 endpoint wraps rows
    /// in `{"entries": [...]}`, `v3.1` decodes a bare `[FlowsheetEntry]`, and
    /// the resulting `typeMismatch` is swallowed by `fetchPlaylist()` into an
    /// empty playlist. Serving v2 to those clients is a silent outage — it
    /// happened on 2026-04-28 and again on 2026-08-10.
    ///
    /// Because this value is baked into each binary, a build can only default
    /// to the version it shipped with. `v3.1` has `.v1` compiled in and cannot
    /// be reached from here, no matter how the flag is configured. That is the
    /// guarantee PostHog release conditions could not give us: every
    /// server-side notion of a client's app version (`$app_version` on events,
    /// on the person record, or in a cohort) is written by the ingestion
    /// pipeline, so it is stale exactly when it matters and absent entirely
    /// while ingestion is down. See #846.
    ///
    /// The feature flag keeps its rollback role — see ``loadActive(featureFlagProvider:defaults:)``.
    public static let defaultVersion: PlaylistAPIVersion = .v2

    /// Loads the active API version to use.
    ///
    /// Priority order:
    /// 1. Manual debug override (if set)
    /// 2. PostHog feature flag
    /// 3. ``defaultVersion``
    ///
    /// Step 2 is now a **kill switch, not a rollout lever**. With `.v2`
    /// compiled in as the default, setting `playlist_api_version` to `v1`
    /// pulls a misbehaving build back without shipping a release; setting it
    /// to `v2` is a no-op for builds that already default there, and remains
    /// actively unsafe for any build older than 3.2.
    public static func loadActive() -> PlaylistAPIVersion {
        loadActive(featureFlagProvider: PostHogFeatureFlagProvider.shared)
    }

    /// Loads the active API version with an injectable feature flag provider.
    ///
    /// - Parameter featureFlagProvider: Provider for feature flag values.
    /// - Returns: The active API version.
    public static func loadActive(featureFlagProvider: FeatureFlagProvider) -> PlaylistAPIVersion {
        loadActive(featureFlagProvider: featureFlagProvider, defaults: defaults)
    }

    /// Internal method with full dependency injection for testing.
    static func loadActive(
        featureFlagProvider: FeatureFlagProvider,
        defaults: DefaultsStorage
    ) -> PlaylistAPIVersion {
        // 1. Check if user manually selected a version in Debug View
        if defaults.bool(forKey: manualSelectionKey),
           let rawValue = defaults.string(forKey: userDefaultsKey),
           let version = PlaylistAPIVersion(rawValue: rawValue) {
            return version
        }

        // 2. Check PostHog feature flag
        if let variant = featureFlagProvider.getFeatureFlag(featureFlagKey) as? String,
           let version = PlaylistAPIVersion(rawValue: variant) {
            return version
        }

        // 3. Fallback to default
        return defaultVersion
    }

    /// Persists a manual override selection.
    public func persist() {
        persist(to: Self.defaults)
    }

    /// Persists a manual override selection to the specified defaults.
    func persist(to defaults: DefaultsStorage) {
        defaults.set(rawValue, forKey: Self.userDefaultsKey)
        defaults.set(true, forKey: Self.manualSelectionKey)
    }

    /// Clears the manual override, reverting to feature flag control.
    public static func clearOverride() {
        clearOverride(from: defaults)
    }

    /// Clears the manual override from the specified defaults.
    static func clearOverride(from defaults: DefaultsStorage) {
        defaults.removeObject(forKey: userDefaultsKey)
        defaults.removeObject(forKey: manualSelectionKey)
    }

    // MARK: - Identifiable

    public var id: String { rawValue }

    // MARK: - Display

    public var displayName: String {
        switch self {
        case .v1:
            "v1 (Legacy)"
        case .v2:
            "v2 (Flowsheet)"
        }
    }

    public var shortDescription: String {
        switch self {
        case .v1:
            "wxyc.info/playlists/recentEntries"
        case .v2:
            "api.wxyc.org/flowsheet"
        }
    }

    // MARK: - Live updates

    /// Whether this API version has a `live-fs-topic` SSE channel to
    /// subscribe to at all.
    ///
    /// This is a **ceiling** on live updates, not the sole determinant:
    /// `PlaylistService` only actually opens a subscription when this is
    /// `true` *and* the caller opted in (`liveUpdatesEnabled`). v1
    /// (`wxyc.info/playlists/recentEntries`) has no push channel, so a poll
    /// is the only way to get fresh data on v1 regardless of caller intent —
    /// `false` here, unconditionally. v2 (`api.wxyc.org/flowsheet`) is the
    /// only version with a `live-fs-topic` stream (see
    /// `FlowsheetLiveEventSource`).
    public var supportsLiveUpdates: Bool {
        switch self {
        case .v1:
            false
        case .v2:
            true
        }
    }
}
