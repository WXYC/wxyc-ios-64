//
//  CriticReviewsFeatureTests.swift
//  WXYC
//
//  Verifies the critic-reviews runtime gate. `resolveEnabled` is the pure
//  decision factored out of `isEnabled` so the Release/PostHog branch — which a
//  Debug test run can't otherwise reach — is exercisable by passing
//  `isDebugBuild:` explicitly. The load-bearing case is Release + flag off/absent
//  staying dark (fail-safe), so the App Store build never surfaces reviews until
//  the PostHog flag is deliberately ramped.
//
//  Created by Jake Bromberg on 07/26/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import Caching
import Testing
@testable import WXYC

/// Minimal in-test FeatureFlagProvider — avoids an AnalyticsTesting dependency.
private struct StubFlags: FeatureFlagProvider {
    var values: [String: Any] = [:]
    func getFeatureFlag(_ key: String) -> Any? { values[key] }
}

@Suite("Critic reviews runtime gate")
struct CriticReviewsFeatureTests {
    // MARK: resolveEnabled (pure)

    @Test("Release build with the flag off or absent stays dark (fail-safe)")
    func releaseDefaultsDark() {
        #expect(CriticReviewsFeature.resolveEnabled(override: nil, isDebugBuild: false, flagValue: nil) == false)
        #expect(CriticReviewsFeature.resolveEnabled(override: nil, isDebugBuild: false, flagValue: false) == false)
    }

    @Test("Release build with the PostHog flag on renders (rollout)")
    func releaseFollowsFlag() {
        #expect(CriticReviewsFeature.resolveEnabled(override: nil, isDebugBuild: false, flagValue: true) == true)
    }

    @Test("Debug build defaults on regardless of the flag")
    func debugDefaultsOn() {
        #expect(CriticReviewsFeature.resolveEnabled(override: nil, isDebugBuild: true, flagValue: nil) == true)
        #expect(CriticReviewsFeature.resolveEnabled(override: nil, isDebugBuild: true, flagValue: false) == true)
    }

    @Test("Debug override wins over both build config and flag")
    func overrideWins() {
        #expect(CriticReviewsFeature.resolveEnabled(override: false, isDebugBuild: true, flagValue: true) == false)
        #expect(CriticReviewsFeature.resolveEnabled(override: true, isDebugBuild: false, flagValue: false) == true)
    }

    // MARK: isEnabled (wiring)

    @Test("isEnabled honors an explicit override over the flag")
    func isEnabledHonorsOverride() {
        let provider = StubFlags(values: [CriticReviewsFeature.featureFlagKey: true])
        let defaults = InMemoryDefaults()
        CriticReviewsFeature.setOverride(false, defaults: defaults)
        #expect(CriticReviewsFeature.isEnabled(featureFlagProvider: provider, defaults: defaults) == false)
        #expect(CriticReviewsFeature.currentOverride(defaults: defaults) == false)
        CriticReviewsFeature.setOverride(nil, defaults: defaults)
        #expect(CriticReviewsFeature.currentOverride(defaults: defaults) == nil)
    }

    // MARK: shouldShowReviews (pure)

    @Test("shouldShowReviews requires both enabled and non-empty reviews")
    func shouldShowReviewsMatrix() {
        #expect(CriticReviewsFeature.shouldShowReviews(isEnabled: true, hasReviews: true))
        #expect(!CriticReviewsFeature.shouldShowReviews(isEnabled: true, hasReviews: false))
        #expect(!CriticReviewsFeature.shouldShowReviews(isEnabled: false, hasReviews: true))
        #expect(!CriticReviewsFeature.shouldShowReviews(isEnabled: false, hasReviews: false))
    }
}
