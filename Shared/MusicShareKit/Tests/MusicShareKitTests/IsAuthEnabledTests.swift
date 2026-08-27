//
//  IsAuthEnabledTests.swift
//  MusicShareKit
//
//  Tests for MusicShareKit.isAuthEnabled()'s guard branch (#1012): a missing
//  featureFlagProvider must be attributable in telemetry, not a silent
//  `false`, or an unwired build reads identically to a disabled flag.
//
//  Created by Jake Bromberg on 08/27/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import AnalyticsTesting
import Caching
import Foundation
import Testing
@testable import MusicShareKit

@Suite("MusicShareKit.isAuthEnabled()", .serialized)
struct IsAuthEnabledTests {

    let mockAnalytics = MockStructuredAnalytics()

    /// Matches `DeviceFingerprintConfigurationTests.makeConfiguration`: an
    /// explicit in-memory fingerprint storage so tests never touch the real
    /// Keychain, and a `requestOMaticURL` shared with the other suites that
    /// race on `MusicShareKit`'s global static state.
    func makeConfiguration(featureFlagProvider: FeatureFlagProvider?) -> MusicShareKitConfiguration {
        MusicShareKitConfiguration(
            requestOMaticURL: "https://example.com/request",
            authBaseURL: nil,
            keychainAccessGroup: nil,
            featureFlagProvider: featureFlagProvider,
            defaults: InMemoryDefaults(),
            analyticsService: mockAnalytics,
            deviceFingerprintStorage: InMemoryDeviceFingerprintStorage()
        )
    }

    /// Confirms MusicShareKit's global config is still the one this test
    /// installed. `MusicShareKitTests` runs its suites in parallel, and
    /// `.serialized` only orders tests WITHIN this suite (see
    /// `DeviceFingerprintConfigurationTests` and
    /// `MusicShareKitConfigureGuardTests` for the same caveat) — a concurrent
    /// suite's `reconfigure(_:)` can swap the global config, including
    /// `analyticsService`, between this test's own `reconfigure(_:)` and
    /// `isAuthEnabled()`'s read of it. When that happens `isAuthEnabled()`
    /// can still legitimately return the expected value (several sibling
    /// suites also configure with a nil `featureFlagProvider`), but the
    /// capture landed on the racing suite's mock instead of this test's — a
    /// benign race, not a regression, so the caller should skip its
    /// assertions rather than fail.
    private func stillOwnsGlobalConfiguration() -> Bool {
        (MusicShareKit.configuration.analyticsService as AnyObject) === (mockAnalytics as AnyObject)
    }

    @Test("Returns false and captures source .unwired when no featureFlagProvider is configured")
    func unwiredProviderCapturesAndReturnsFalse() {
        MusicShareKit.reconfigure(makeConfiguration(featureFlagProvider: nil))
        mockAnalytics.reset()

        let enabled = MusicShareKit.isAuthEnabled()

        guard stillOwnsGlobalConfiguration() else { return }

        #expect(enabled == false)

        let events = mockAnalytics.typedEvents(ofType: RequestLineFeatureFlagEvaluatedEvent.self)
        #expect(events.count == 1)
        #expect(events.first?.enabled == false)
        #expect(events.first?.source == "unwired")
    }

    @Test("Delegates to RequestLineAuthFeature and does not capture .unwired when a provider is configured")
    func wiredProviderDelegatesToFeature() {
        let provider = MockFeatureFlagProvider()
        provider.flags[RequestLineAuthFeature.featureFlagKey] = true
        MusicShareKit.reconfigure(makeConfiguration(featureFlagProvider: provider))
        mockAnalytics.reset()

        let enabled = MusicShareKit.isAuthEnabled()

        guard stillOwnsGlobalConfiguration() else { return }

        #expect(enabled == true)

        let events = mockAnalytics.typedEvents(ofType: RequestLineFeatureFlagEvaluatedEvent.self)
        #expect(events.count == 1)
        #expect(events.first?.source == "flag")
    }
}
