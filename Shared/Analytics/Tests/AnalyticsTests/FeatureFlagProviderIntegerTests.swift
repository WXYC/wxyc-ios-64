//
//  FeatureFlagProviderIntegerTests.swift
//  Analytics
//
//  Covers the integer-flag read used by the On Tour "Heard on WXYC" shelf's
//  station-recommended tier cap (#493/#577): a remotely-tunable count that must
//  degrade to a sensible local default when the flag is absent, offline, or a
//  non-numeric shape.
//
//  Created by Jake Bromberg on 07/19/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Analytics
import AnalyticsTesting

@Suite("Feature flag integer read")
struct FeatureFlagProviderIntegerTests {

    @Test("An absent flag falls back to the default")
    func absentUsesDefault() {
        let provider = MockFeatureFlagProvider()
        #expect(provider.integerValue(forKey: "on_tour_for_you_station_cap", default: 3) == 3)
    }

    @Test("An Int flag value is returned")
    func intValue() {
        let provider = MockFeatureFlagProvider()
        provider.flags["cap"] = 5
        #expect(provider.integerValue(forKey: "cap", default: 3) == 5)
    }

    @Test("A Double flag value is truncated to Int")
    func doubleValue() {
        let provider = MockFeatureFlagProvider()
        provider.flags["cap"] = 4.0
        #expect(provider.integerValue(forKey: "cap", default: 3) == 4)
    }

    @Test("A fractional Double is truncated toward zero")
    func fractionalDoubleTruncates() {
        let provider = MockFeatureFlagProvider()
        provider.flags["cap"] = 4.9
        #expect(provider.integerValue(forKey: "cap", default: 3) == 4)
    }

    @Test("A non-finite or out-of-range Double falls back to the default", arguments: [
        Double.nan, .infinity, -.infinity, 1e300, -1e300,
    ])
    func unusableDoubleUsesDefault(_ value: Double) {
        // The whole contract is a graceful default; `Int(_:)` would trap on any
        // of these, so the shelf must never build the cap from them.
        let provider = MockFeatureFlagProvider()
        provider.flags["cap"] = value
        #expect(provider.integerValue(forKey: "cap", default: 3) == 3)
    }

    @Test("A numeric String variant is parsed")
    func numericStringValue() {
        // PostHog delivers a multivariate variant as its key string; a numeric
        // variant like "7" must coerce so the cap can be tuned without a payload.
        let provider = MockFeatureFlagProvider()
        provider.flags["cap"] = "7"
        #expect(provider.integerValue(forKey: "cap", default: 3) == 7)
    }

    @Test("A non-numeric String falls back to the default")
    func nonNumericStringUsesDefault() {
        let provider = MockFeatureFlagProvider()
        provider.flags["cap"] = "control"
        #expect(provider.integerValue(forKey: "cap", default: 3) == 3)
    }

    @Test("A Bool flag falls back to the default")
    func boolUsesDefault() {
        // A boolean flag is the wrong shape for a cap; don't coerce true→1.
        let provider = MockFeatureFlagProvider()
        provider.flags["cap"] = true
        #expect(provider.integerValue(forKey: "cap", default: 3) == 3)
    }
}
