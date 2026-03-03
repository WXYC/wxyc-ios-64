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
}
