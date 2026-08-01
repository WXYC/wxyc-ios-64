//
//  DeferredSessionTokenProviderTests.swift
//  Core
//
//  Tests for `DeferredSessionTokenProvider`: the resolve-per-call wrapper
//  that fixes the construction-order nil capture where `Singletonia`'s
//  stored properties are built (forcing `Singletonia.shared`) before
//  `MusicShareKit.configure(...)` runs in `WXYCApp.init()`. Confirms the
//  wrapper re-reads its resolver on every call instead of freezing whatever
//  the resolver returned at construction time.
//
//  Created by Jake Bromberg on 07/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import CoreTesting
import Testing
@testable import Core

@Suite
struct DeferredSessionTokenProviderTests {

    @Test("Resolves the provider per call, not at construction, so a provider wired up after construction is still picked up")
    func resolvesPerCallNotAtConstruction() async throws {
        let box = ProviderBox()
        // Constructed while the box (standing in for `MusicShareKit.authService`
        // before `configure(...)` has run) is nil.
        let deferred = DeferredSessionTokenProvider { box.provider }

        await #expect(throws: SessionTokenProviderError.notConfigured) {
            _ = try await deferred.token()
        }

        // Simulate `configure(...)` running later and wiring up a real provider.
        box.provider = RecordingTokenProvider(initialToken: "post-configure-token")

        // The SAME wrapper instance, constructed while the box was nil, now
        // resolves successfully — proving resolution happens per call, not
        // once at construction.
        let token = try await deferred.token()
        #expect(token == "post-configure-token")
    }

    @Test("token() throws notConfigured when the resolver returns nil at call time")
    func tokenThrowsWhenResolverReturnsNil() async throws {
        let deferred = DeferredSessionTokenProvider { nil }

        await #expect(throws: SessionTokenProviderError.notConfigured) {
            _ = try await deferred.token()
        }
    }

    @Test("reauthenticate(previousToken:) throws notConfigured when the resolver returns nil at call time")
    func reauthenticateThrowsWhenResolverReturnsNil() async throws {
        let deferred = DeferredSessionTokenProvider { nil }

        await #expect(throws: SessionTokenProviderError.notConfigured) {
            _ = try await deferred.reauthenticate(previousToken: "expired-token")
        }
    }

    @Test("token() forwards to the resolved provider's token()")
    func tokenForwardsToResolvedProvider() async throws {
        let stub = RecordingTokenProvider(initialToken: "forwarded-token")
        let deferred = DeferredSessionTokenProvider { stub }

        let token = try await deferred.token()
        #expect(token == "forwarded-token")
    }

    @Test("reauthenticate(previousToken:) forwards previousToken and returns the resolved provider's value")
    func reauthenticateForwardsToResolvedProvider() async throws {
        let stub = RecordingTokenProvider(refreshedToken: "forwarded-reauthenticated-token")
        let deferred = DeferredSessionTokenProvider { stub }

        let token = try await deferred.reauthenticate(previousToken: "rejected-token")
        #expect(token == "forwarded-reauthenticated-token")
        #expect(await stub.lastPreviousToken == "rejected-token")
    }
}
