//
//  SessionTokenProvider.swift
//  Core
//
//  Protocol for providing session tokens to services that need authenticated
//  access to backend proxy endpoints. Implementations live in MusicShareKit
//  (full AuthenticationService) and AppServices (keychain-only fallback).
//
//  Created by Jake Bromberg on 03/03/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Provides a session token for authenticated API calls.
///
/// Services that call backend proxy endpoints accept an optional
/// `SessionTokenProvider` at initialization. When present, they include
/// the token in an `Authorization: Bearer <token>` header.
public protocol SessionTokenProvider: Sendable {
    /// Returns a valid session token, performing authentication if needed.
    func token() async throws -> String

    /// Forces a fresh session token, discarding any cached/stored one that
    /// still matches `previousToken`.
    ///
    /// Callers reach for this after a server rejects the token `token()`
    /// returned (a 401 response) — the cached token is stale or was revoked
    /// server-side, so retrying with the same value would just 401 again.
    /// `previousToken` is the exact value that was rejected; conformers use
    /// it to tell "nobody has refreshed since I got 401'd" (do the work)
    /// apart from "another caller already refreshed past this" (hand back
    /// what's cached now, no redundant network round trip).
    ///
    /// This is a concurrency-sensitive method: a burst of authed calls that
    /// all 401 on the same rejected token (e.g. several proxy fetches firing
    /// at once on a cold launch with a stale session) must produce exactly
    /// one fresh sign-in, and every caller must receive that same fresh
    /// token — none should see a spurious cancellation just because another
    /// caller's recovery ran first. The concrete `AuthenticationService`
    /// (MusicShareKit) implements this by coalescing concurrent callers onto
    /// a single in-flight sign-in rather than cancelling and restarting one
    /// another. Declared here, on the protocol, so callers in `Concerts` and
    /// `Metadata` can trigger that recovery without depending on
    /// MusicShareKit directly.
    func reauthenticate(previousToken: String) async throws -> String
}

/// A `SessionTokenProvider` was asked for a token before one was configured.
///
/// Thrown by ``DeferredSessionTokenProvider`` when its resolver closure
/// still returns `nil` at call time — e.g. a proxy request fires before
/// `MusicShareKit.configure(...)` has wired up the real
/// `AuthenticationService`.
public enum SessionTokenProviderError: Error, Equatable {
    case notConfigured
}

extension SessionTokenProviderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            "No session token provider is configured yet."
        }
    }
}
