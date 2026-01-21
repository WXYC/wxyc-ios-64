//
//  AuthSessionTests.swift
//  MusicShareKit
//
//  Tests for AuthSession model and expiration logic.
//
//  Created by Jake Bromberg on 01/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import MusicShareKit

@Suite("AuthSession Tests")
struct AuthSessionTests {

    @Test("Session without expiration is never expired")
    func sessionWithoutExpirationNeverExpires() {
        let session = AuthSession(
            token: "test-token",
            userId: "test-user",
            createdAt: Date().addingTimeInterval(-86400), // Created yesterday
            expiresAt: nil
        )

        #expect(session.isExpired == false)
    }

    @Test("Session with future expiration is not expired")
    func sessionWithFutureExpirationNotExpired() {
        let session = AuthSession(
            token: "test-token",
            userId: "test-user",
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(3600) // Expires in 1 hour
        )

        #expect(session.isExpired == false)
    }

    @Test("Session with past expiration is expired")
    func sessionWithPastExpirationIsExpired() {
        let session = AuthSession(
            token: "test-token",
            userId: "test-user",
            createdAt: Date().addingTimeInterval(-7200), // Created 2 hours ago
            expiresAt: Date().addingTimeInterval(-3600) // Expired 1 hour ago
        )

        #expect(session.isExpired == true)
    }

    @Test("Session expiring now is considered expired")
    func sessionExpiringNowIsExpired() {
        let session = AuthSession(
            token: "test-token",
            userId: "test-user",
            createdAt: Date().addingTimeInterval(-3600),
            expiresAt: Date() // Expires right now
        )

        #expect(session.isExpired == true)
    }

    @Test("Session is Codable")
    func sessionIsCodable() throws {
        let original = AuthSession(
            token: "test-token",
            userId: "test-user",
            createdAt: Date(timeIntervalSince1970: 1000000),
            expiresAt: Date(timeIntervalSince1970: 2000000)
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AuthSession.self, from: data)

        #expect(decoded.token == original.token)
        #expect(decoded.userId == original.userId)
        #expect(decoded.createdAt == original.createdAt)
        #expect(decoded.expiresAt == original.expiresAt)
    }

    @Test("Session with nil expiresAt is Codable")
    func sessionWithNilExpiresAtIsCodable() throws {
        let original = AuthSession(
            token: "test-token",
            userId: "test-user",
            createdAt: Date(timeIntervalSince1970: 1000000),
            expiresAt: nil
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AuthSession.self, from: data)

        #expect(decoded.token == original.token)
        #expect(decoded.userId == original.userId)
        #expect(decoded.expiresAt == nil)
    }
}
