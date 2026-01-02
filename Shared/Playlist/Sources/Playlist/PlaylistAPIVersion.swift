//
//  PlaylistAPIVersion.swift
//  Playlist
//
//  Controls which playlist API version to use via PostHog feature flag.
//

import Foundation
import PostHog
import Caching

// MARK: - Feature Flag Provider Protocol

/// Protocol for retrieving feature flag values, allowing PostHogSDK to be mocked in tests.
public protocol FeatureFlagProvider {
    func getFeatureFlag(_ key: String) -> Any?
}

extension PostHogSDK: FeatureFlagProvider {}

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

    /// The default API version
    public static let defaultVersion: PlaylistAPIVersion = .v1

    /// Loads the active API version to use.
    ///
    /// Priority order:
    /// 1. Manual debug override (if set)
    /// 2. PostHog feature flag
    /// 3. Default to v1
    public static func loadActive() -> PlaylistAPIVersion {
        loadActive(featureFlagProvider: PostHogSDK.shared)
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
        defaults: UserDefaults
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
    func persist(to defaults: UserDefaults) {
        defaults.set(rawValue, forKey: Self.userDefaultsKey)
        defaults.set(true, forKey: Self.manualSelectionKey)
    }

    /// Clears the manual override, reverting to feature flag control.
    public static func clearOverride() {
        clearOverride(from: defaults)
    }

    /// Clears the manual override from the specified defaults.
    static func clearOverride(from defaults: UserDefaults) {
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
}
