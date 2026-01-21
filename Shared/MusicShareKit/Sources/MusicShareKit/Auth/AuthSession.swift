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

/// Represents an anonymous authentication session.
public struct AuthSession: Codable, Sendable, Equatable {

    /// The bearer token for authenticated requests.
    public let token: String

    /// The anonymous user identifier assigned by the server.
    public let userId: String

    /// When this session was created.
    public let createdAt: Date

    /// When this session expires, if known.
    public let expiresAt: Date?

    /// Creates a new authentication session.
    ///
    /// - Parameters:
    ///   - token: The bearer token for authenticated requests.
    ///   - userId: The anonymous user identifier.
    ///   - createdAt: When this session was created. Defaults to now.
    ///   - expiresAt: When this session expires, if known.
    public init(
        token: String,
        userId: String,
        createdAt: Date = Date(),
        expiresAt: Date? = nil
    ) {
        self.token = token
        self.userId = userId
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }

    /// Whether this session has expired.
    ///
    /// Returns `false` if no expiration is set.
    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() >= expiresAt
    }
}
