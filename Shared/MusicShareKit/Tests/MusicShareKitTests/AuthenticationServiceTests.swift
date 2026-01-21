//
//  AuthenticationServiceTests.swift
//  MusicShareKit
//
//  Tests for AuthenticationService token management and authentication flow.
//
//  Created by Jake Bromberg on 01/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AnalyticsTesting
import Foundation
import Testing
@testable import MusicShareKit

@Suite("AuthenticationService Tests")
struct AuthenticationServiceTests {

    // MARK: - Test Fixtures

    let mockAnalytics = MockStructuredAnalytics()

    func makeService(
        storage: TokenStorage = InMemoryTokenStorage(),
        networkClient: AuthNetworkClient = MockAuthNetworkClient(),
        baseURL: String = "https://api.example.com"
    ) -> AuthenticationService {
        AuthenticationService(
            storage: storage,
            networkClient: networkClient,
            baseURL: baseURL,
            analytics: mockAnalytics
        )
    }

    func makeValidSession(expiresIn: TimeInterval = 3600) -> AuthSession {
        AuthSession(
            token: "test-token-\(UUID().uuidString)",
            userId: "test-user-\(UUID().uuidString)",
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(expiresIn)
        )
    }

    func makeExpiredSession() -> AuthSession {
        AuthSession(
            token: "expired-token",
            userId: "expired-user",
            createdAt: Date().addingTimeInterval(-7200),
            expiresAt: Date().addingTimeInterval(-3600)
        )
    }

    // MARK: - ensureAuthenticated Tests

    @Test("Returns cached token when available and not expired")
    func returnsCachedToken() async throws {
        let storage = InMemoryTokenStorage()
        let networkClient = MockAuthNetworkClient()
        let session = makeValidSession()

        // Pre-populate storage
        try storage.save(session)

        let service = makeService(storage: storage, networkClient: networkClient)

        // First call should load from storage
        let token1 = try await service.ensureAuthenticated()
        #expect(token1 == session.token)

        // Second call should return cached (no additional storage/network calls)
        let token2 = try await service.ensureAuthenticated()
        #expect(token2 == session.token)
        #expect(networkClient.signInCallCount == 0)
    }

    @Test("Loads from storage when cache is empty")
    func loadsFromStorage() async throws {
        let storage = InMemoryTokenStorage()
        let networkClient = MockAuthNetworkClient()
        let session = makeValidSession()

        try storage.save(session)

        let service = makeService(storage: storage, networkClient: networkClient)
        let token = try await service.ensureAuthenticated()

        #expect(token == session.token)
        #expect(networkClient.signInCallCount == 0)
    }

    @Test("Signs in anonymously when no stored session")
    func signsInWhenNoStoredSession() async throws {
        let storage = InMemoryTokenStorage()
        let networkClient = MockAuthNetworkClient()
        let session = makeValidSession()
        networkClient.mockSession = session

        let service = makeService(storage: storage, networkClient: networkClient)
        let token = try await service.ensureAuthenticated()

        #expect(token == session.token)
        #expect(networkClient.signInCallCount == 1)

        // Verify session was saved to storage
        let storedSession = try storage.load()
        #expect(storedSession?.token == session.token)
    }

    @Test("Signs in when stored session is expired")
    func signsInWhenSessionExpired() async throws {
        let storage = InMemoryTokenStorage()
        let networkClient = MockAuthNetworkClient()

        // Store an expired session
        let expiredSession = makeExpiredSession()
        try storage.save(expiredSession)

        // Network will return a fresh session
        let freshSession = makeValidSession()
        networkClient.mockSession = freshSession

        let service = makeService(storage: storage, networkClient: networkClient)
        let token = try await service.ensureAuthenticated()

        #expect(token == freshSession.token)
        #expect(networkClient.signInCallCount == 1)
    }

    @Test("Throws error when network sign-in fails")
    func throwsOnNetworkFailure() async throws {
        let storage = InMemoryTokenStorage()
        let networkClient = MockAuthNetworkClient()
        networkClient.mockError = AuthenticationError.networkError(URLError(.notConnectedToInternet))

        let service = makeService(storage: storage, networkClient: networkClient)

        await #expect(throws: AuthenticationError.self) {
            _ = try await service.ensureAuthenticated()
        }
    }

    // MARK: - reauthenticate Tests

    @Test("Reauthenticate clears cache and fetches fresh token")
    func reauthenticateClearsCacheAndRefetches() async throws {
        let storage = InMemoryTokenStorage()
        let networkClient = MockAuthNetworkClient()

        // Initial session
        let initialSession = makeValidSession()
        try storage.save(initialSession)

        // Fresh session from reauthentication
        let freshSession = makeValidSession()
        networkClient.mockSession = freshSession

        let service = makeService(storage: storage, networkClient: networkClient)

        // First, get the initial token (from storage)
        let token1 = try await service.ensureAuthenticated()
        #expect(token1 == initialSession.token)

        // Now reauthenticate
        let token2 = try await service.reauthenticate(reason: .unauthorized)
        #expect(token2 == freshSession.token)
        #expect(networkClient.signInCallCount == 1)
    }

    // MARK: - currentUserId Tests

    @Test("Returns user ID from cached session")
    func returnsUserIdFromCache() async throws {
        let storage = InMemoryTokenStorage()
        let session = makeValidSession()
        try storage.save(session)

        let service = makeService(storage: storage)

        // First call loads into cache
        _ = try await service.ensureAuthenticated()

        // Now get user ID
        let userId = await service.currentUserId()
        #expect(userId == session.userId)
    }

    @Test("Returns nil when not authenticated")
    func returnsNilWhenNotAuthenticated() async {
        let storage = InMemoryTokenStorage()
        let service = makeService(storage: storage)

        let userId = await service.currentUserId()
        #expect(userId == nil)
    }

    // MARK: - signOut Tests

    @Test("Sign out clears cached session and storage")
    func signOutClearsEverything() async throws {
        let storage = InMemoryTokenStorage()
        let networkClient = MockAuthNetworkClient()
        let session = makeValidSession()

        try storage.save(session)
        networkClient.mockSession = makeValidSession() // For re-auth after sign out

        let service = makeService(storage: storage, networkClient: networkClient)

        // Load into cache
        _ = try await service.ensureAuthenticated()

        // Sign out
        await service.signOut()

        // Storage should be empty
        let storedSession = try storage.load()
        #expect(storedSession == nil)

        // User ID should be nil
        let userId = await service.currentUserId()
        #expect(userId == nil)
    }

    // MARK: - Analytics Tests

    @Test("Tracks auth started and completed events")
    func tracksAuthEvents() async throws {
        let storage = InMemoryTokenStorage()
        let networkClient = MockAuthNetworkClient()
        networkClient.mockSession = makeValidSession()

        let service = makeService(storage: storage, networkClient: networkClient)
        mockAnalytics.reset()

        _ = try await service.ensureAuthenticated()

        let eventNames = mockAnalytics.capturedEventNames()
        #expect(eventNames.contains("request_line_auth_started"))
        #expect(eventNames.contains("request_line_auth_completed"))
    }

    @Test("Tracks auth failed event on network error")
    func tracksAuthFailedOnNetworkError() async throws {
        let storage = InMemoryTokenStorage()
        let networkClient = MockAuthNetworkClient()
        networkClient.mockError = AuthenticationError.networkError(URLError(.timedOut))

        let service = makeService(storage: storage, networkClient: networkClient)
        mockAnalytics.reset()

        do {
            _ = try await service.ensureAuthenticated()
        } catch {
            // Expected
        }

        let eventNames = mockAnalytics.capturedEventNames()
        #expect(eventNames.contains("request_line_auth_failed"))
    }
}
