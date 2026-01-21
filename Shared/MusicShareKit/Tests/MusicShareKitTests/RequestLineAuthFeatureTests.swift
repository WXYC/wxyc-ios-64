//
//  RequestLineAuthFeatureTests.swift
//  MusicShareKit
//
//  Tests for RequestLineAuthFeature flag evaluation with override support.
//
//  Created by Jake Bromberg on 01/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import AnalyticsTesting
import Caching
import Foundation
import Testing
@testable import MusicShareKit

@Suite("RequestLineAuthFeature Tests")
struct RequestLineAuthFeatureTests {

    let mockAnalytics = MockStructuredAnalytics()

    // MARK: - Feature Flag Tests

    @Test("Returns false when feature flag is disabled")
    func returnsFalseWhenFlagDisabled() {
        let defaults = InMemoryDefaults()
        let provider = MockFeatureFlagProvider()
        provider.flags["request_line_auth_enabled"] = false

        let enabled = RequestLineAuthFeature.isEnabled(
            featureFlagProvider: provider,
            defaults: defaults,
            analytics: mockAnalytics
        )

        #expect(enabled == false)
    }

    @Test("Returns true when feature flag is enabled")
    func returnsTrueWhenFlagEnabled() {
        let defaults = InMemoryDefaults()
        let provider = MockFeatureFlagProvider()
        provider.flags["request_line_auth_enabled"] = true

        let enabled = RequestLineAuthFeature.isEnabled(
            featureFlagProvider: provider,
            defaults: defaults,
            analytics: mockAnalytics
        )

        #expect(enabled == true)
    }

    @Test("Returns false when feature flag is not set")
    func returnsFalseWhenFlagNotSet() {
        let defaults = InMemoryDefaults()
        let provider = MockFeatureFlagProvider()
        // Don't set the flag - should default to false

        let enabled = RequestLineAuthFeature.isEnabled(
            featureFlagProvider: provider,
            defaults: defaults,
            analytics: mockAnalytics
        )

        #expect(enabled == false)
    }

    // MARK: - Override Tests

    @Test("Override takes precedence over feature flag - override true")
    func overrideTrueOverridesFlag() {
        let defaults = InMemoryDefaults()
        let provider = MockFeatureFlagProvider()
        provider.flags["request_line_auth_enabled"] = false // Flag says disabled

        // Set override to true
        RequestLineAuthFeature.setOverride(true, defaults: defaults)

        let enabled = RequestLineAuthFeature.isEnabled(
            featureFlagProvider: provider,
            defaults: defaults,
            analytics: mockAnalytics
        )

        #expect(enabled == true)
    }

    @Test("Override takes precedence over feature flag - override false")
    func overrideFalseOverridesFlag() {
        let defaults = InMemoryDefaults()
        let provider = MockFeatureFlagProvider()
        provider.flags["request_line_auth_enabled"] = true // Flag says enabled

        // Set override to false
        RequestLineAuthFeature.setOverride(false, defaults: defaults)

        let enabled = RequestLineAuthFeature.isEnabled(
            featureFlagProvider: provider,
            defaults: defaults,
            analytics: mockAnalytics
        )

        #expect(enabled == false)
    }

    @Test("Clear override reverts to feature flag")
    func clearOverrideRevertsToFlag() {
        let defaults = InMemoryDefaults()
        let provider = MockFeatureFlagProvider()
        provider.flags["request_line_auth_enabled"] = true

        // Set and then clear override
        RequestLineAuthFeature.setOverride(false, defaults: defaults)
        RequestLineAuthFeature.clearOverride(defaults: defaults)

        let enabled = RequestLineAuthFeature.isEnabled(
            featureFlagProvider: provider,
            defaults: defaults,
            analytics: mockAnalytics
        )

        #expect(enabled == true)
    }

    @Test("Current override returns set value")
    func currentOverrideReturnsSetValue() {
        let defaults = InMemoryDefaults()

        #expect(RequestLineAuthFeature.currentOverride(defaults: defaults) == nil)

        RequestLineAuthFeature.setOverride(true, defaults: defaults)
        #expect(RequestLineAuthFeature.currentOverride(defaults: defaults) == true)

        RequestLineAuthFeature.setOverride(false, defaults: defaults)
        #expect(RequestLineAuthFeature.currentOverride(defaults: defaults) == false)

        RequestLineAuthFeature.clearOverride(defaults: defaults)
        #expect(RequestLineAuthFeature.currentOverride(defaults: defaults) == nil)
    }

    // MARK: - Analytics Tests

    @Test("Tracks feature flag evaluation with flag source")
    func tracksEvaluationWithFlagSource() {
        let defaults = InMemoryDefaults()
        let provider = MockFeatureFlagProvider()
        provider.flags["request_line_auth_enabled"] = true
        mockAnalytics.reset()

        _ = RequestLineAuthFeature.isEnabled(
            featureFlagProvider: provider,
            defaults: defaults,
            analytics: mockAnalytics
        )

        let events = mockAnalytics.events(named: "request_line_feature_flag_evaluated")
        #expect(events.count == 1)

        if let props = events.first?.properties {
            #expect(props["enabled"] as? Bool == true)
            #expect(props["source"] as? String == "flag")
        }
    }

    @Test("Tracks feature flag evaluation with override source")
    func tracksEvaluationWithOverrideSource() {
        let defaults = InMemoryDefaults()
        let provider = MockFeatureFlagProvider()
        provider.flags["request_line_auth_enabled"] = false
        mockAnalytics.reset()

        RequestLineAuthFeature.setOverride(true, defaults: defaults)

        _ = RequestLineAuthFeature.isEnabled(
            featureFlagProvider: provider,
            defaults: defaults,
            analytics: mockAnalytics
        )

        let events = mockAnalytics.events(named: "request_line_feature_flag_evaluated")
        #expect(events.count == 1)

        if let props = events.first?.properties {
            #expect(props["enabled"] as? Bool == true)
            #expect(props["source"] as? String == "override")
        }
    }
}

// MARK: - Mock Feature Flag Provider

final class MockFeatureFlagProvider: FeatureFlagProvider {
    var flags: [String: Any] = [:]

    func getFeatureFlag(_ key: String) -> Any? {
        flags[key]
    }
}
