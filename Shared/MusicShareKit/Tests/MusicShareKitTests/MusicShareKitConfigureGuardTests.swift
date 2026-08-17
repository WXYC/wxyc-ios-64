//
//  MusicShareKitConfigureGuardTests.swift
//  MusicShareKit
//
//  Tests that MusicShareKit.configure(_:) is a once-per-process no-op after
//  its first call (#956): the share extension's ShareViewController calls
//  configure(_:) on every presentation, and without the guard that rebuilds
//  _authService from scratch each time, dropping the in-memory
//  cachedSession the #948 Keychain-miss fallback depends on.
//
//  This is the ONLY suite in this test process that calls configure(_:) —
//  every other suite that needs a guaranteed rebuild with fresh doubles
//  calls reconfigure(_:) instead (see the four suites named in #956). That
//  keeps this suite's identity assertion below meaningful: a passing
//  `.serialized` run here is not racing another suite's configure(_:) call
//  for the same static guard.
//
//  Created by Jake Bromberg on 08/17/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AnalyticsTesting
import Foundation
import Testing
@testable import MusicShareKit

@Suite("MusicShareKit.configure(_:) once-per-process guard", .serialized)
struct MusicShareKitConfigureGuardTests {

    let mockAnalytics = MockStructuredAnalytics()

    @Test("A second configure() call does not rebuild authService")
    func secondConfigureCallPreservesAuthServiceIdentity() throws {
        MusicShareKit.configure(MusicShareKitConfiguration(
            requestOMaticURL: "https://example.com/request",
            authBaseURL: "https://api.example.com",
            keychainAccessGroup: nil,
            featureFlagProvider: nil,
            defaults: UserDefaults.standard,
            analyticsService: mockAnalytics,
            deviceFingerprintStorage: InMemoryDeviceFingerprintStorage()
        ))
        let firstAuthService = try #require(MusicShareKit.authService)

        // Models ShareViewController.viewDidLoad's second (and every later)
        // presentation: same call, a differently-shaped config, same
        // process. Without the guard this rebuilds _authService, dropping
        // whatever cachedSession the first presentation accumulated.
        MusicShareKit.configure(MusicShareKitConfiguration(
            requestOMaticURL: "https://example.com/request-2",
            authBaseURL: "https://api.example.com/2",
            keychainAccessGroup: nil,
            featureFlagProvider: nil,
            defaults: UserDefaults.standard,
            analyticsService: mockAnalytics,
            deviceFingerprintStorage: InMemoryDeviceFingerprintStorage()
        ))

        #expect(MusicShareKit.authService === firstAuthService)
    }
}
