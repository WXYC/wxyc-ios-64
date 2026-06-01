//
//  AuthSession.swift
//  MusicShareKit
//
//  Data model representing an anonymous authentication session.
//
//  Created by Jake Bromberg on 01/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Represents a complete anonymous authentication session.
///
/// The session token is the long-lived refresh credential (~30 days,
/// server-side row in `auth_session`). The JWT is the short-lived API bearer
/// (~15 min) we attach as `Authorization: Bearer <jwt>` on authenticated
/// requests. Both are needed: the session token lets us mint fresh JWTs
/// without re-signing-in (and so without churning `auth_user` rows every JWT
/// lifetime, which would defeat the user-id ban path).
public struct AuthSession: Codable, Sendable, Equatable {

    /// The long-lived session refresh credential (better-auth `auth_session`).
    public let sessionToken: String

    /// The short-lived JWT used as Bearer on authenticated requests.
    public let jwt: String

    /// The anonymous user identifier assigned by the server.
    public let userId: String

    /// When this session was created.
    public let createdAt: Date

    /// When this JWT expires.
    public let expiresAt: Date?

    /// Creates a new authentication session.
    ///
    /// - Parameters:
    ///   - sessionToken: The long-lived session refresh credential.
    ///   - jwt: The short-lived JWT used as Bearer on authenticated requests.
    ///   - userId: The anonymous user identifier.
    ///   - createdAt: When this session was created. Defaults to now.
    ///   - expiresAt: When this JWT expires.
    public init(
        sessionToken: String,
        jwt: String,
        userId: String,
        createdAt: Date = Date(),
        expiresAt: Date? = nil
    ) {
        self.sessionToken = sessionToken
        self.jwt = jwt
        self.userId = userId
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }

    /// Whether the JWT in this session is expired.
    ///
    /// Returns `false` if no expiration is set.
    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() >= expiresAt
    }

    /// Returns whether the JWT is stale within `margin` seconds of its
    /// `expiresAt`. Use this for the "refresh proactively" path so we don't
    /// ship a JWT that expires mid-flight.
    public func jwtIsStale(margin: TimeInterval) -> Bool {
        guard let expiresAt else { return false }
        return Date().addingTimeInterval(margin) >= expiresAt
    }

    /// Returns a copy of this session with a new JWT (and matching expiry).
    /// Used after `/auth/token` mints a fresh JWT for an existing session.
    public func with(jwt newJWT: String, expiresAt newExpiresAt: Date?) -> AuthSession {
        AuthSession(
            sessionToken: sessionToken,
            jwt: newJWT,
            userId: userId,
            createdAt: createdAt,
            expiresAt: newExpiresAt
        )
    }
}

/// Result of an anonymous sign-in call. Carries the session token (long-lived
/// refresh credential) and the assigned user id — but not the JWT, which is
/// fetched in a subsequent `/auth/token` exchange.
public struct AnonymousSignInResult: Sendable, Equatable {

    /// The long-lived session token returned by `/sign-in/anonymous`.
    public let sessionToken: String

    /// The anonymous user identifier assigned by the server.
    public let userId: String

    public init(sessionToken: String, userId: String) {
        self.sessionToken = sessionToken
        self.userId = userId
    }
}
