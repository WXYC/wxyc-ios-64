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

// MARK: - PostHog Implementation

/// Feature flag provider backed by PostHog.
public struct PostHogFeatureFlagProvider: FeatureFlagProvider, Sendable {
    public static let shared = PostHogFeatureFlagProvider()

    public init() {}

    public func getFeatureFlag(_ key: String) -> Any? {
        PostHogSDK.shared.getFeatureFlag(key)
    }
}
