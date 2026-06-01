//
//  InMemoryTokenStorageTests.swift
//  MusicShareKit
//
//  Tests for InMemoryTokenStorage test double.
//
//  Created by Jake Bromberg on 01/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import MusicShareKit

@Suite("InMemoryTokenStorage Tests")
struct InMemoryTokenStorageTests {

    func makeValidSession() -> AuthSession {
        AuthSession(
            sessionToken: "test-session-token",
            jwt: "test-jwt",
            userId: "test-user",
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(3600)
        )
    }

    @Test("Load returns nil when empty")
    func loadReturnsNilWhenEmpty() throws {
        let storage = InMemoryTokenStorage()
        let session = try storage.load()
        #expect(session == nil)
    }

    @Test("Save and load round-trips session")
    func saveAndLoadRoundTrips() throws {
        let storage = InMemoryTokenStorage()
        let session = makeValidSession()

        try storage.save(session)
        let loaded = try storage.load()

        #expect(loaded?.jwt == session.jwt)
        #expect(loaded?.sessionToken == session.sessionToken)
        #expect(loaded?.userId == session.userId)
    }

    @Test("Delete removes stored session")
    func deleteRemovesSession() throws {
        let storage = InMemoryTokenStorage()
        let session = makeValidSession()

        try storage.save(session)
        try storage.delete()
        let loaded = try storage.load()

        #expect(loaded == nil)
    }

    @Test("Delete on empty storage does not throw")
    func deleteOnEmptyDoesNotThrow() throws {
        let storage = InMemoryTokenStorage()
        try storage.delete() // Should not throw
    }

    @Test("Save overwrites existing session")
    func saveOverwritesExisting() throws {
        let storage = InMemoryTokenStorage()

        let session1 = AuthSession(
            sessionToken: "session-1",
            jwt: "jwt-1",
            userId: "user-1",
            createdAt: Date(),
            expiresAt: nil
        )
        let session2 = AuthSession(
            sessionToken: "session-2",
            jwt: "jwt-2",
            userId: "user-2",
            createdAt: Date(),
            expiresAt: nil
        )

        try storage.save(session1)
        try storage.save(session2)

        let loaded = try storage.load()
        #expect(loaded?.jwt == "jwt-2")
        #expect(loaded?.sessionToken == "session-2")
        #expect(loaded?.userId == "user-2")
    }
}
