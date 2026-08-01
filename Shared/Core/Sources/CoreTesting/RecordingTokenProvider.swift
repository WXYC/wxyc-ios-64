//
//  RecordingTokenProvider.swift
//  CoreTesting
//
//  The canonical `SessionTokenProvider` test double. Replaces the per-target
//  clones that drifted apart: CoreTests' `StubTokenProvider`,
//  `GatedTokenProvider` (AuthedDataTests) and `StubProvider`
//  (DeferredSessionTokenProviderTests), ConcertsTests'
//  `FixedTokenProvider`/`RecordingTokenProvider`, MetadataTests'
//  `MockTokenProvider`, and AppServicesTests' `RecordingTokenProvider`.
//
//  Created by Jake Bromberg on 07/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Core

/// A `SessionTokenProvider` returning a fixed `token()` and a fixed —
/// deliberately different — `reauthenticate(previousToken:)` value, recording
/// calls so tests can assert both "reauthenticated exactly once" and "the
/// retry carried the new token".
///
/// The distinct-by-default `refreshedToken` is structural, not conventional:
/// a double whose `reauthenticate` hands back the same token it already
/// served violates the protocol's "forces a fresh token" contract and lets a
/// same-token-retry regression pass unnoticed. (MetadataTests'
/// `MockTokenProvider` had exactly that default, guarded only by a ⚠️ doc
/// warning.) Tests that genuinely want identical values — e.g. asserting a
/// bearer header without exercising the retry path — pass the same string
/// for both.
///
/// For concurrency-ordering tests, `gateReauthentication: true` parks
/// `reauthenticate(previousToken:)` until `release()` is called, so a test
/// can cancel a caller while its reauthentication is still in flight (the
/// former `GatedTokenProvider`).
public actor RecordingTokenProvider: SessionTokenProvider {

    /// How many times `token()` was called.
    public private(set) var tokenCallCount = 0

    /// How many times `reauthenticate(previousToken:)` was called.
    public private(set) var reauthenticateCallCount = 0

    /// The `previousToken` most recently passed to
    /// `reauthenticate(previousToken:)`, or `nil` if it was never called.
    public private(set) var lastPreviousToken: String?

    /// Whether `reauthenticate(previousToken:)` has begun executing. Distinct
    /// from `reauthenticateCallCount` only in gated mode, where a test polls
    /// this to know the caller is parked before cancelling it.
    public private(set) var reauthenticateStarted = false

    private let initialToken: String
    private let refreshedToken: String
    private let gateReauthentication: Bool
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(
        initialToken: String = "initial-token",
        refreshedToken: String = "refreshed-token",
        gateReauthentication: Bool = false
    ) {
        self.initialToken = initialToken
        self.refreshedToken = refreshedToken
        self.gateReauthentication = gateReauthentication
    }

    public func token() async throws -> String {
        tokenCallCount += 1
        return initialToken
    }

    public func reauthenticate(previousToken: String) async throws -> String {
        reauthenticateStarted = true
        lastPreviousToken = previousToken
        reauthenticateCallCount += 1
        if gateReauthentication, !released {
            await withCheckedContinuation { waiters.append($0) }
        }
        return refreshedToken
    }

    /// Resumes every caller parked in a gated `reauthenticate(previousToken:)`
    /// and lets all future calls pass straight through. No-op when
    /// `gateReauthentication` is `false`.
    public func release() {
        released = true
        for waiter in waiters {
            waiter.resume()
        }
        waiters.removeAll()
    }
}
