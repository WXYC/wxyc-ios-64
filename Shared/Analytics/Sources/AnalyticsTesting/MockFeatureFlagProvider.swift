//
//  MockFeatureFlagProvider.swift
//  AnalyticsTesting
//
//  Test double for FeatureFlagProvider that returns configurable flag values.
//  Replaces the identical MockFeatureFlagProvider classes scattered across test targets.
//
//  Created by Jake Bromberg on 03/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics

/// Test double for ``FeatureFlagProvider`` that returns configurable flag values.
///
/// Set flag values via the ``flags`` dictionary, then inject this provider
/// into the code under test.
///
/// ```swift
/// let provider = MockFeatureFlagProvider()
/// provider.flags["my_feature"] = true
/// let enabled = MyFeature.isEnabled(featureFlagProvider: provider)
/// ```
public final class MockFeatureFlagProvider: FeatureFlagProvider {
    /// The flag values to return from ``getFeatureFlag(_:)``.
    public var flags: [String: Any] = [:]

    public init() {}

    public func getFeatureFlag(_ key: String) -> Any? {
        flags[key]
    }
}
