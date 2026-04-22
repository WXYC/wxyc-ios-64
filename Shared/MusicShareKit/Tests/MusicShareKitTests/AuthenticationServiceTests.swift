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

    /// Creates a mock network client configured for the two-step auth flow.
    func makeNetworkClient(session: AuthSession, jwtExpiresIn: TimeInterval = 3600) -> MockAuthNetworkClient {
        let client = MockAuthNetworkClient()
        client.mockSession = session
        client.mockJWT = makeTestJWT(expiresIn: jwtExpiresIn)
        return client
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

    @Test("Signs in and exchanges for JWT when no stored session")
    func signsInWhenNoStoredSession() async throws {
        let storage = InMemoryTokenStorage()
        let signInSession = makeValidSession()
        let networkClient = makeNetworkClient(session: signInSession)

        let service = makeService(storage: storage, networkClient: networkClient)
        let token = try await service.ensureAuthenticated()

        // Returned token should be the JWT, not the session token
        #expect(token != signInSession.token)
        #expect(token.contains("."))
        #expect(networkClient.signInCallCount == 1)
        #expect(networkClient.fetchJWTCallCount == 1)

        // Verify stored session has the JWT and a non-nil expiration
        let storedSession = try storage.load()
        #expect(storedSession?.token == token)
        #expect(storedSession?.expiresAt != nil)
    }

    @Test("Signs in when stored session is expired")
    func signsInWhenSessionExpired() async throws {
        let storage = InMemoryTokenStorage()

        // Store an expired session
        let expiredSession = makeExpiredSession()
        try storage.save(expiredSession)

        // Network will return a fresh session + JWT
        let freshSession = makeValidSession()
        let networkClient = makeNetworkClient(session: freshSession)

        let service = makeService(storage: storage, networkClient: networkClient)
        let token = try await service.ensureAuthenticated()

        // Should be the JWT, not the sign-in session token
        #expect(token != freshSession.token)
        #expect(token.contains("."))
        #expect(networkClient.signInCallCount == 1)
        #expect(networkClient.fetchJWTCallCount == 1)
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

    @Test("Throws error when JWT exchange fails")
    func throwsOnJWTExchangeFailure() async throws {
        let storage = InMemoryTokenStorage()
        let networkClient = MockAuthNetworkClient()
        networkClient.mockSession = makeValidSession()
        networkClient.mockJWTError = AuthenticationError.serverError(statusCode: 500)

        let service = makeService(storage: storage, networkClient: networkClient)

        await #expect(throws: AuthenticationError.self) {
            _ = try await service.ensureAuthenticated()
        }

        // Sign-in should have been called, but JWT exchange failed
        #expect(networkClient.signInCallCount == 1)
        #expect(networkClient.fetchJWTCallCount == 1)
    }

    @Test("Stored JWT session with valid expiration skips network calls")
    func cachedJWTSessionSkipsNetwork() async throws {
        let storage = InMemoryTokenStorage()
        let networkClient = MockAuthNetworkClient()

        // Pre-populate storage with a JWT session (has expiresAt)
        let jwtSession = AuthSession(
            token: "eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjk5OTk5OTk5OTl9.sig",
            userId: "user-123",
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(3600)
        )
        try storage.save(jwtSession)

        let service = makeService(storage: storage, networkClient: networkClient)
        let token = try await service.ensureAuthenticated()

        #expect(token == jwtSession.token)
        #expect(networkClient.signInCallCount == 0)
        #expect(networkClient.fetchJWTCallCount == 0)
    }

    @Test("Expired JWT session triggers full re-auth with JWT exchange")
    func expiredJWTSessionTriggersFullReauth() async throws {
        let storage = InMemoryTokenStorage()

        // Store an expired JWT session
        let expiredJWT = AuthSession(
            token: "eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjF9.sig",
            userId: "user-123",
            createdAt: Date().addingTimeInterval(-7200),
            expiresAt: Date().addingTimeInterval(-3600)
        )
        try storage.save(expiredJWT)

        let freshSession = makeValidSession()
        let networkClient = makeNetworkClient(session: freshSession)

        let service = makeService(storage: storage, networkClient: networkClient)
        let token = try await service.ensureAuthenticated()

        #expect(token.contains("."))
        #expect(networkClient.signInCallCount == 1)
        #expect(networkClient.fetchJWTCallCount == 1)
    }

    // MARK: - reauthenticate Tests

    @Test("Reauthenticate clears cache and fetches fresh token")
    func reauthenticateClearsCacheAndRefetches() async throws {
        let storage = InMemoryTokenStorage()

        // Initial session (already in storage, bypasses network)
        let initialSession = makeValidSession()
        try storage.save(initialSession)

        // Fresh session from reauthentication (will go through network)
        let freshSession = makeValidSession()
        let networkClient = makeNetworkClient(session: freshSession)

        let service = makeService(storage: storage, networkClient: networkClient)

        // First, get the initial token (from storage)
        let token1 = try await service.ensureAuthenticated()
        #expect(token1 == initialSession.token)

        // Now reauthenticate
        let token2 = try await service.reauthenticate(reason: .unauthorized)
        #expect(token2 != initialSession.token)
        #expect(networkClient.signInCallCount == 1)
        #expect(networkClient.fetchJWTCallCount == 1)
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
        let session = makeValidSession()
        try storage.save(session)

        let networkClient = makeNetworkClient(session: makeValidSession())

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
        let session = makeValidSession()
        let networkClient = makeNetworkClient(session: session)

        let service = makeService(storage: storage, networkClient: networkClient)
        mockAnalytics.reset()

        _ = try await service.ensureAuthenticated()

        let eventNames = mockAnalytics.capturedEventNames()
        #expect(eventNames.contains("request_line_auth_started_event"))
        #expect(eventNames.contains("request_line_auth_completed_event"))
    }

    @Test("Tracks JWT exchange event on successful auth from network")
    func tracksJWTExchangeEvent() async throws {
        let storage = InMemoryTokenStorage()
        let session = makeValidSession()
        let networkClient = makeNetworkClient(session: session)

        let service = makeService(storage: storage, networkClient: networkClient)
        mockAnalytics.reset()

        _ = try await service.ensureAuthenticated()

        let eventNames = mockAnalytics.capturedEventNames()
        #expect(eventNames.contains("request_line_jwt_exchange_event"))
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
        #expect(eventNames.contains("request_line_auth_failed_event"))
    }

    @Test("Tracks auth failed event with jwtExchange phase on JWT exchange error")
    func tracksJWTExchangeFailure() async throws {
        let storage = InMemoryTokenStorage()
        let networkClient = MockAuthNetworkClient()
        networkClient.mockSession = makeValidSession()
        networkClient.mockJWTError = AuthenticationError.serverError(statusCode: 500)

        let service = makeService(storage: storage, networkClient: networkClient)
        mockAnalytics.reset()

        do {
            _ = try await service.ensureAuthenticated()
        } catch {
            // Expected
        }

        let failedEvents = mockAnalytics.typedEvents(ofType: RequestLineAuthFailedEvent.self)
        let jwtExchangeFailure = failedEvents.first { $0.phase == .jwtExchange }
        #expect(jwtExchangeFailure != nil)
    }
}

// MARK: - Test Helpers

/// Creates a test JWT with a valid payload containing the given expiration.
///
/// The JWT is structurally valid (three base64url segments with a decodable payload)
/// but has a fake signature — this is sufficient for `JWTPayloadDecoder` which does
/// not verify signatures.
private func makeTestJWT(expiresIn: TimeInterval = 3600) -> String {
    let header = Data("{\"alg\":\"HS256\"}".utf8).base64EncodedString()
    let exp = Int(Date().addingTimeInterval(expiresIn).timeIntervalSince1970)
    let payload = Data("{\"sub\":\"test\",\"exp\":\(exp)}".utf8).base64EncodedString()

    func base64urlEncode(_ base64: String) -> String {
        base64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    return "\(base64urlEncode(header)).\(base64urlEncode(payload)).fakesignature"
}
