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
//  Every assertion below is scoped to a test-local
//  InMemoryDeviceFingerprintStorage rather than to MusicShareKit's process
//  globals. That matters: MusicShareKitTests runs its suites in parallel,
//  and `.serialized` only orders tests WITHIN a suite, so a concurrent
//  reconfigure(_:) from another suite — MusicShareKitTokenProviderTests
//  installs a non-nil authBaseURL — can replace _authService mid-test. An
//  assertion on `MusicShareKit.authService`'s identity would therefore fail
//  spuriously, and read as a real regression. Nothing outside this test can
//  touch the storage doubles, so the assertions here can't race.
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

    @Test("A second configure() call does not rebuild MusicShareKit's globals")
    func secondConfigureCallIsANoOp() throws {
        // A once-per-process guarantee tests itself vacuously the moment
        // something else has already consumed the gate: every call this test
        // makes would be a no-op, so the assertions below would hold without
        // the guard doing any work. Fail loudly instead. If this trips, some
        // other suite started calling configure(_:) where it should call
        // reconfigure(_:) — or this suite ran twice in one process.
        try #require(
            MusicShareKit.configureGate.hasRun == false,
            "configure(_:)'s gate was already consumed before this test ran, which would make the assertions below vacuous"
        )

        let firstStorage = InMemoryDeviceFingerprintStorage()
        MusicShareKit.configure(MusicShareKitConfiguration(
            requestOMaticURL: "https://example.com/request",
            // Discard-port base URLs, matching
            // MusicShareKitTokenProviderTests: these calls write
            // MusicShareKit's global _authService, and a suite racing us
            // could resolve it and attempt a sign-in. Pointing at 127.0.0.1:9
            // makes that fail fast with connection-refused rather than
            // leaving the network from a unit test.
            authBaseURL: "http://127.0.0.1:9",
            keychainAccessGroup: nil,
            featureFlagProvider: nil,
            defaults: UserDefaults.standard,
            analyticsService: mockAnalytics,
            deviceFingerprintStorage: firstStorage
        ))

        // The first call in a process must do the real work: reconfigure(_:)
        // eagerly materializes the fingerprint before building the auth
        // service, so exactly one ensure() proves the rebuild ran.
        #expect(firstStorage.ensureCallCount == 1, "the first configure(_:) in a process must run the full rebuild")

        // Models ShareViewController.viewDidLoad's second (and every later)
        // presentation: same call, a differently-shaped config, same
        // process. Without the guard this reruns the whole rebuild —
        // materializing this config's fingerprint and replacing
        // _authService, dropping whatever cachedSession the first
        // presentation accumulated.
        let secondStorage = InMemoryDeviceFingerprintStorage()
        MusicShareKit.configure(MusicShareKitConfiguration(
            requestOMaticURL: "https://example.com/request-2",
            authBaseURL: "http://127.0.0.1:9/second",
            keychainAccessGroup: nil,
            featureFlagProvider: nil,
            defaults: UserDefaults.standard,
            analyticsService: mockAnalytics,
            deviceFingerprintStorage: secondStorage
        ))

        // reconfigure(_:) is all-or-nothing, and ensure() is its first step.
        // An untouched second storage therefore proves the second call never
        // entered the rebuild at all — so it cannot have replaced
        // _authService either.
        #expect(secondStorage.ensureCallCount == 0, "a second configure(_:) in the same process must not rebuild anything")
        #expect(MusicShareKit.configureGate.hasRun)
    }
}
