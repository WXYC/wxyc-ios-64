//
//  CriticReviewsFeature.swift
//  WXYC
//
//  Runtime gate for the external critic-reviews card in PlaycutDetailView
//  (ADR 0012). Mirrors the RequestLineAuthFeature / PlaylistAPIVersion feature
//  pattern: a debug override wins, then Debug builds default on (so dev and
//  TestFlight always render for testing), then the PostHog flag decides — and
//  it defaults OFF, so a Release/App Store build stays dark until the flag is
//  deliberately ramped from the PostHog dashboard (and can be killed the same
//  way). The backend has its own `CRITIC_REVIEWS_ENABLED` serve flag; both must
//  be on for a card to appear (no data served → nothing to show regardless).
//
//  Created by Jake Bromberg on 07/26/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import Caching
import Foundation

/// Runtime visibility gate for the critic-reviews card.
enum CriticReviewsFeature {
    /// PostHog feature flag key (Release rollout control).
    static let featureFlagKey = "critic_reviews_ios_enabled"

    /// Defaults key for the manual debug override.
    private static let manualOverrideKey = "debug.criticReviewsEnabled"

    /// Whether this binary was compiled in the Debug configuration.
    static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// Pure resolution of the gate, factored out so every branch — including the
    /// Release/PostHog path a Debug test run can't otherwise reach — is unit
    /// testable. Priority: explicit debug override → Debug build defaults on →
    /// PostHog flag, defaulting off (fail-safe dark).
    /// - Parameters:
    ///   - override: The debug override value, or `nil` when unset.
    ///   - isDebugBuild: The build configuration this binary was compiled in.
    ///   - flagValue: The PostHog flag value, or `nil` when absent/offline/wrong-shape.
    static func resolveEnabled(override: Bool?, isDebugBuild: Bool, flagValue: Bool?) -> Bool {
        if let override { return override }
        if isDebugBuild { return true }
        return flagValue ?? false
    }

    /// Resolves whether the feature is enabled for this build, reading the debug
    /// override from `defaults` and the flag from `featureFlagProvider`.
    static func isEnabled(
        featureFlagProvider: FeatureFlagProvider,
        defaults: DefaultsStorage = UserDefaults.standard
    ) -> Bool {
        resolveEnabled(
            override: defaults.object(forKey: manualOverrideKey) as? Bool,
            isDebugBuild: isDebugBuild,
            flagValue: featureFlagProvider.getFeatureFlag(featureFlagKey) as? Bool
        )
    }

    /// Pure render decision for `PlaycutDetailView`: show the card iff the feature
    /// is enabled AND the album carries at least one critic review.
    static func shouldShowReviews(isEnabled: Bool, hasReviews: Bool) -> Bool {
        isEnabled && hasReviews
    }

    // MARK: - Debug override

    /// Sets (or clears, with `nil`) the manual override used by the debug menu.
    static func setOverride(_ enabled: Bool?, defaults: DefaultsStorage = UserDefaults.standard) {
        if let enabled {
            defaults.set(enabled, forKey: manualOverrideKey)
        } else {
            defaults.removeObject(forKey: manualOverrideKey)
        }
    }

    /// Returns the current debug override value, if set.
    static func currentOverride(defaults: DefaultsStorage = UserDefaults.standard) -> Bool? {
        defaults.object(forKey: manualOverrideKey) as? Bool
    }
}
