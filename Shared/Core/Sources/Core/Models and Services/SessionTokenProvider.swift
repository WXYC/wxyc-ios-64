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

    /// Forces a fresh session token, discarding any cached/stored one.
    ///
    /// Callers reach for this after a server rejects the token `token()`
    /// returned (a 401 response) — the cached token is stale or was revoked
    /// server-side, so retrying with the same value would just 401 again.
    /// The concrete `AuthenticationService` (MusicShareKit) implements this
    /// by clearing its cached/keychain session and signing in fresh; it's
    /// declared here, on the protocol, so callers in `Concerts` and
    /// `Metadata` can trigger that recovery without depending on
    /// MusicShareKit directly.
    func reauthenticate() async throws -> String
}
