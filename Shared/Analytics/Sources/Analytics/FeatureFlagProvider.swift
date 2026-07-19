//
//  FeatureFlagProvider.swift
//  Analytics
//
//  Protocol for retrieving feature flag values, with PostHog implementation.
//
//  Created by Jake Bromberg on 01/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import PostHog

// MARK: - Feature Flag Provider Protocol

/// Protocol for retrieving feature flag values.
///
/// Allows packages to check feature flags without directly depending on PostHog,
/// and enables mocking in tests.
public protocol FeatureFlagProvider {
    /// Retrieves the value of a feature flag.
    ///
    /// - Parameter key: The feature flag key.
    /// - Returns: The flag value, or `nil` if not set.
    func getFeatureFlag(_ key: String) -> Any?
}

public extension FeatureFlagProvider {
    /// Reads a feature flag as an integer, falling back to `defaultValue` when the
    /// flag is absent, offline, or the wrong shape.
    ///
    /// PostHog can deliver a numeric flag as an `Int` or `Double`, and a
    /// multivariate flag as its variant key `String` (so a numeric variant like
    /// `"7"` arrives as text); all three coerce. A boolean flag — the wrong shape
    /// for a count — and any non-numeric string yield the default rather than a
    /// surprising `true → 1`.
    ///
    /// A `Double` that isn't a finite, in-`Int`-range value (NaN, ±∞, or a
    /// magnitude past `Int.max`, e.g. a misconfigured `1e300`) also falls back to
    /// the default: `Int(exactly:)` guards the conversion so an unusable numeric
    /// flag degrades gracefully instead of trapping.
    ///
    /// - Parameters:
    ///   - key: The feature flag key.
    ///   - defaultValue: The value returned when the flag is unusable. This is the
    ///     local default that keeps the feature working offline.
    /// - Returns: The resolved integer, or `defaultValue`.
    func integerValue(forKey key: String, default defaultValue: Int) -> Int {
        switch getFeatureFlag(key) {
        case is Bool:
            // A boolean flag is not a count; don't coerce true→1 / false→0.
            return defaultValue
        case let value as Int:
            return value
        case let value as Double:
            // Truncate toward zero, but only when the result is a finite,
            // in-range integer — `Int(_:)` traps on NaN/±∞/overflow.
            return Int(exactly: value.rounded(.towardZero)) ?? defaultValue
        case let value as String:
            return Int(value) ?? defaultValue
        default:
            return defaultValue
        }
    }
}

// MARK: - PostHog Implementation

/// Feature flag provider backed by PostHog.
public struct PostHogFeatureFlagProvider: FeatureFlagProvider, Sendable {
    public static let shared = PostHogFeatureFlagProvider()

    public init() {}

    public func getFeatureFlag(_ key: String) -> Any? {
        PostHogSDK.shared.getFeatureFlag(key)
    }
}
