//
//  MusicShareKitTokenProviderTests.swift
//  MusicShareKit
//
//  Tests for the MusicShareKit.tokenProvider facade: a late-binding
//  SessionTokenProvider that resolves authService at each call, so
//  construction sites that run before configure() (Singletonia's
//  stored-property initializers) can never freeze a nil authService.
//
//  Created by Jake Bromberg on 07/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AnalyticsTesting
import Core
import Foundation
import Testing
@testable import MusicShareKit

@Suite("MusicShareKit token-provider facade", .serialized)
struct MusicShareKitTokenProviderTests {

    let mockAnalytics = MockStructuredAnalytics()

    @Test("a provider handed out before configure() resolves the post-configure authService")
    func facadeResolvesPerCall() async throws {
        // Captured the way Singletonia's stored-property initializers capture
        // it — before WXYCApp.init() has run configure(). The facade must
        // resolve authService at each call, not at construction (#718).
        let provider = MusicShareKit.tokenProvider

        // No other suite configures with a non-nil authBaseURL, so this is
        // the only setter of MusicShareKit's global authService in the test
        // process. The discard-port baseURL makes any attempted sign-in fail
        // fast with connection-refused instead of leaving the network.
        // `requestOMaticURL` matches the other suites' value because configure
        // races across parallel suites are last-write-wins (see the note in
        // DeviceFingerprintConfigurationTests.makeConfiguration).
        let fingerprintStorage = InMemoryDeviceFingerprintStorage()
        fingerprintStorage.stubFingerprint = "fp-facade-\(UUID().uuidString)"
        MusicShareKit.configure(MusicShareKitConfiguration(
            requestOMaticURL: "https://example.com/request",
            authBaseURL: "http://127.0.0.1:9",
            keychainAccessGroup: nil,
            featureFlagProvider: nil,
            defaults: UserDefaults.standard,
            analyticsService: mockAnalytics,
            deviceFingerprintStorage: fingerprintStorage
        ))

        do {
            _ = try await provider.token()
            Issue.record("expected a throw — no auth server is listening at the test baseURL")
        } catch is SessionTokenProviderError {
            Issue.record("facade froze a pre-configure nil authService — the #718 bug class")
        } catch {
            // Reaching the real AuthenticationService is the passing outcome.
            // Keychain (errSecMissingEntitlement in this SPM bundle) or
            // network (connection refused), the failure it surfaces is an
            // AuthenticationError — proof the call resolved past the facade.
            #expect(error is AuthenticationError)
        }
    }
}
