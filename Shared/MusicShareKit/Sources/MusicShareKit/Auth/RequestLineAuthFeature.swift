//
//  RequestLineAuthFeature.swift
//  MusicShareKit
//
//  Controls whether anonymous authentication is used for request line requests
//  via PostHog feature flag with debug override support.
//
//  Created by Jake Bromberg on 01/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import Caching
import Foundation

// MARK: - RequestLineAuthFeature

/// Controls whether anonymous authentication is enabled for request line requests.
///
/// Priority order:
/// 1. Debug override (if set in defaults)
/// 2. PostHog feature flag
/// 3. Default to disabled
public enum RequestLineAuthFeature {

    /// PostHog feature flag key
    public static let featureFlagKey = "request_line_auth_enabled"

    /// Defaults key for manual override
    private static let manualOverrideKey = "debug.requestLineAuthEnabled"

    // MARK: - Checking Feature Status

    /// Checks whether request line authentication is enabled.
    ///
    /// - Parameters:
    ///   - featureFlagProvider: Provider for feature flag values.
    ///   - defaults: Defaults storage for debug override.
    ///   - analytics: Analytics service for tracking flag evaluation.
    /// - Returns: `true` if authentication should be used, `false` otherwise.
    public static func isEnabled(
        featureFlagProvider: FeatureFlagProvider,
        defaults: DefaultsStorage,
        analytics: AnalyticsService
    ) -> Bool {
        // 1. Check debug override
        if let override = defaults.object(forKey: manualOverrideKey) as? Bool {
            analytics.capture(RequestLineFeatureFlagEvaluatedEvent(
                enabled: override,
                source: .override
            ))
            return override
        }

        // 2. Check PostHog feature flag
        let enabled = featureFlagProvider.getFeatureFlag(featureFlagKey) as? Bool ?? false
        analytics.capture(RequestLineFeatureFlagEvaluatedEvent(
            enabled: enabled,
            source: .flag
        ))
        return enabled
    }

    // MARK: - Debug Override

    /// Sets a debug override for the authentication feature.
    ///
    /// - Parameters:
    ///   - enabled: The override value, or `nil` to clear the override.
    ///   - defaults: Defaults storage for the override.
    public static func setOverride(_ enabled: Bool?, defaults: DefaultsStorage) {
        if let enabled {
            defaults.set(enabled, forKey: manualOverrideKey)
        } else {
            defaults.removeObject(forKey: manualOverrideKey)
        }
    }

    /// Clears any debug override, reverting to feature flag control.
    ///
    /// - Parameter defaults: Defaults storage for the override.
    public static func clearOverride(defaults: DefaultsStorage) {
        defaults.removeObject(forKey: manualOverrideKey)
    }

    /// Returns the current debug override value, if set.
    ///
    /// - Parameter defaults: Defaults storage for the override.
    /// - Returns: The override value, or `nil` if not overridden.
    public static func currentOverride(defaults: DefaultsStorage) -> Bool? {
        defaults.object(forKey: manualOverrideKey) as? Bool
    }
}
