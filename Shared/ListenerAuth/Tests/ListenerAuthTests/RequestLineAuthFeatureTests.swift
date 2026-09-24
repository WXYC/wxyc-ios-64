//
//  RequestLineAuthFeatureTests.swift
//  ListenerAuth
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
@testable import ListenerAuth

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

        let events = mockAnalytics.events(named: "request_line_feature_flag_evaluated_event")
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

        let events = mockAnalytics.events(named: "request_line_feature_flag_evaluated_event")
        #expect(events.count == 1)

        if let props = events.first?.properties {
            #expect(props["enabled"] as? Bool == true)
            #expect(props["source"] as? String == "override")
        }
    }

    // MARK: - Unwired Provider Tests (#1012)

    /// A missing `featureFlagProvider` is `isEnabled`'s own step 3, not a
    /// guard the caller implements — see the type's doc comment. Before this,
    /// the only capture site for "no provider was wired" lived in
    /// `MusicShareKit.isAuthEnabled()`'s guard branch, reachable only through
    /// `MusicShareKit`'s process-global config; testing it there cost ~92
    /// lines of `.serialized` suite plus a race-ownership guard. Widening
    /// `featureFlagProvider` to optional moves the case into this function's
    /// own collaborators-as-parameters shape, so it costs a few lines here
    /// instead.
    @Test("Returns false and captures source .unwired when featureFlagProvider is nil")
    func returnsFalseAndCapturesUnwiredWhenProviderIsNil() {
        let defaults = InMemoryDefaults()
        mockAnalytics.reset()

        let enabled = RequestLineAuthFeature.isEnabled(
            featureFlagProvider: nil,
            defaults: defaults,
            analytics: mockAnalytics
        )

        #expect(enabled == false)

        let events = mockAnalytics.typedEvents(ofType: RequestLineFeatureFlagEvaluatedEvent.self)
        #expect(events.count == 1)
        #expect(events.first?.enabled == false)
        #expect(events.first?.source == "unwired")
    }

    @Test("Debug override still takes precedence when featureFlagProvider is nil")
    func overrideTakesPrecedenceWhenProviderIsNil() {
        let defaults = InMemoryDefaults()
        RequestLineAuthFeature.setOverride(true, defaults: defaults)
        mockAnalytics.reset()

        let enabled = RequestLineAuthFeature.isEnabled(
            featureFlagProvider: nil,
            defaults: defaults,
            analytics: mockAnalytics
        )

        #expect(enabled == true)

        let events = mockAnalytics.typedEvents(ofType: RequestLineFeatureFlagEvaluatedEvent.self)
        #expect(events.count == 1)
        #expect(events.first?.source == "override")
    }
}

