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
import Security
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
            sessionToken: "test-session-\(UUID().uuidString)",
            jwt: "test-jwt-\(UUID().uuidString)",
            userId: "test-user-\(UUID().uuidString)",
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(expiresIn)
        )
    }

    func makeExpiredSession() -> AuthSession {
        AuthSession(
            sessionToken: "expired-session",
            jwt: "expired-jwt",
            userId: "expired-user",
            createdAt: Date().addingTimeInterval(-7200),
            expiresAt: Date().addingTimeInterval(-3600)
        )
    }

    func makeSignInResult() -> AnonymousSignInResult {
        AnonymousSignInResult(
            sessionToken: "signin-session-\(UUID().uuidString)",
            userId: "signin-user-\(UUID().uuidString)"
        )
    }

    /// Creates a mock network client configured for the two-step auth flow.
    func makeNetworkClient(
        signInResult: AnonymousSignInResult? = nil,
        jwtExpiresIn: TimeInterval = 3600
    ) -> MockAuthNetworkClient {
        let client = MockAuthNetworkClient()
        client.mockSignInResult = signInResult ?? makeSignInResult()
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
        #expect(token1 == session.jwt)

        // Second call should return cached (no additional storage/network calls)
        let token2 = try await service.ensureAuthenticated()
        #expect(token2 == session.jwt)
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

        #expect(token == session.jwt)
        #expect(networkClient.signInCallCount == 0)
    }

    @Test("Signs in and exchanges for JWT when no stored session")
    func signsInWhenNoStoredSession() async throws {
        let storage = InMemoryTokenStorage()
        let signInSession = makeSignInResult()
        let networkClient = makeNetworkClient(signInResult: signInSession)

        let service = makeService(storage: storage, networkClient: networkClient)
        let token = try await service.ensureAuthenticated()

        // Returned token should be the JWT, not the session token
        #expect(token != signInSession.sessionToken)
        #expect(token.contains("."))
        #expect(networkClient.signInCallCount == 1)
        #expect(networkClient.fetchJWTCallCount == 1)

        // Verify stored session has the JWT and a non-nil expiration
        let storedSession = try storage.load()
        #expect(storedSession?.jwt == token)
        #expect(storedSession?.expiresAt != nil)
    }

    @Test("Refreshes JWT via /auth/token when stored JWT is expired but session is valid")
    func refreshesJWTWhenJWTExpired() async throws {
        let storage = InMemoryTokenStorage()

        // Store an expired JWT but with a still-valid sessionToken.
        let expiredSession = makeExpiredSession()
        try storage.save(expiredSession)

        // Network mock will return a fresh JWT from /auth/token. No sign-in.
        let networkClient = makeNetworkClient()

        let service = makeService(storage: storage, networkClient: networkClient)
        let token = try await service.ensureAuthenticated()

        #expect(token.contains("."))
        // KEY ASSERTION: /auth/token refresh, NOT re-sign-in (D5).
        #expect(networkClient.signInCallCount == 0)
        #expect(networkClient.fetchJWTCallCount == 1)

        // The fetchJWT call used the persisted sessionToken (not a fresh one).
        #expect(networkClient.fetchJWTSessionTokens == [expiredSession.sessionToken])
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
        networkClient.mockSignInResult = makeSignInResult()
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
            sessionToken: "session-token-123",
            jwt: "eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjk5OTk5OTk5OTl9.sig",
            userId: "user-123",
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(3600)
        )
        try storage.save(jwtSession)

        let service = makeService(storage: storage, networkClient: networkClient)
        let token = try await service.ensureAuthenticated()

        #expect(token == jwtSession.jwt)
        #expect(networkClient.signInCallCount == 0)
        #expect(networkClient.fetchJWTCallCount == 0)
    }

    @Test("401 from /auth/token triggers fresh re-sign-in")
    func refreshFallsBackToSignInOn401() async throws {
        let storage = InMemoryTokenStorage()
        let expiredSession = makeExpiredSession()
        try storage.save(expiredSession)

        // First fetchJWT (refresh attempt) returns 401, second (after re-sign-in)
        // succeeds. Use a stateful mock to script this sequence.
        let networkClient = SequentialJWTMock()
        networkClient.mockSignInResult = makeSignInResult()
        networkClient.fetchJWTOutcomes = [
            .failure(AuthenticationError.serverError(statusCode: 401)),
            .success(makeTestJWT())
        ]

        let service = makeService(storage: storage, networkClient: networkClient)
        let token = try await service.ensureAuthenticated()

        #expect(token.contains("."))
        // Fresh sign-in DID happen because of the 401 fallback.
        #expect(networkClient.signInCallCount == 1)
        // Two fetchJWT calls: the failed refresh, then the post-sign-in mint.
        #expect(networkClient.fetchJWTCallCount == 2)
    }

    @Test("404 from /auth/token triggers fresh re-sign-in")
    func refreshFallsBackToSignInOn404() async throws {
        let storage = InMemoryTokenStorage()
        let expiredSession = makeExpiredSession()
        try storage.save(expiredSession)

        let networkClient = SequentialJWTMock()
        networkClient.mockSignInResult = makeSignInResult()
        networkClient.fetchJWTOutcomes = [
            .failure(AuthenticationError.serverError(statusCode: 404)),
            .success(makeTestJWT())
        ]

        let service = makeService(storage: storage, networkClient: networkClient)
        let token = try await service.ensureAuthenticated()

        #expect(token.contains("."))
        #expect(networkClient.signInCallCount == 1)
        #expect(networkClient.fetchJWTCallCount == 2)
    }

    @Test("500 from /auth/token propagates without re-sign-in")
    func refreshDoesNotFallBackOn500() async throws {
        let storage = InMemoryTokenStorage()
        let expiredSession = makeExpiredSession()
        try storage.save(expiredSession)

        let networkClient = SequentialJWTMock()
        networkClient.mockSignInResult = makeSignInResult()
        networkClient.fetchJWTOutcomes = [
            .failure(AuthenticationError.serverError(statusCode: 500))
        ]

        let service = makeService(storage: storage, networkClient: networkClient)
        await #expect(throws: AuthenticationError.self) {
            _ = try await service.ensureAuthenticated()
        }
        // No re-sign-in for non-401/404.
        #expect(networkClient.signInCallCount == 0)
    }

    // MARK: - D5 Concurrent-Call Dedup

    @Test("Concurrent callers share one in-flight refresh")
    func concurrentCallersDedup() async throws {
        let storage = InMemoryTokenStorage()
        let networkClient = GatedNetworkMock()
        networkClient.mockSignInResult = makeSignInResult()
        networkClient.gateJWT = true
        let mintedJWT = makeTestJWT()
        networkClient.jwtToReturn = mintedJWT

        let service = makeService(storage: storage, networkClient: networkClient)

        // Spawn N concurrent callers. They should all race into the
        // dedup branch and share a single in-flight refresh.
        let n = 5
        async let results: [String] = withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<n {
                group.addTask {
                    try await service.ensureAuthenticated()
                }
            }
            var collected: [String] = []
            for try await value in group {
                collected.append(value)
            }
            return collected
        }

        // Give all callers a moment to enter the actor before we release the gate.
        try await Task.sleep(nanoseconds: 50_000_000)  // 50ms
        networkClient.releaseJWT()

        let tokens = try await results
        #expect(tokens.count == n)
        #expect(tokens.allSatisfy { $0 == mintedJWT })
        // Critical: exactly ONE fetchJWT call, not N.
        #expect(networkClient.fetchJWTCallCount == 1)
        #expect(networkClient.signInCallCount == 1)
    }

    @Test("Refresh failure propagates and clears in-flight handle for next call")
    func refreshFailureDoesNotPoisonDedup() async throws {
        let storage = InMemoryTokenStorage()
        let networkClient = SequentialJWTMock()
        // Configure: signIn always succeeds, first fetchJWT throws (non-401),
        // second fetchJWT succeeds.
        networkClient.mockSignInResult = makeSignInResult()
        networkClient.fetchJWTOutcomes = [
            .failure(AuthenticationError.networkError(URLError(.timedOut))),
            .success(makeTestJWT())
        ]

        let service = makeService(storage: storage, networkClient: networkClient)

        await #expect(throws: AuthenticationError.self) {
            _ = try await service.ensureAuthenticated()
        }

        // Next call must start a NEW refresh — inFlightAuth was cleared by
        // the defer, so the second caller isn't blocked waiting on a stale
        // Task that already threw.
        let token = try await service.ensureAuthenticated()
        #expect(token.contains("."))
        // Two sign-ins (both attempts), two fetchJWT calls (failure + success).
        #expect(networkClient.signInCallCount == 2)
        #expect(networkClient.fetchJWTCallCount == 2)
    }

    // MARK: - reauthenticate Tests

    @Test("Reauthenticate clears cache and fetches fresh token")
    func reauthenticateClearsCacheAndRefetches() async throws {
        let storage = InMemoryTokenStorage()

        // Initial session (already in storage, bypasses network)
        let initialSession = makeValidSession()
        try storage.save(initialSession)

        // Fresh session from reauthentication (will go through network)
        let freshSession = makeSignInResult()
        let networkClient = makeNetworkClient(signInResult: freshSession)

        let service = makeService(storage: storage, networkClient: networkClient)

        // First, get the initial token (from storage)
        let token1 = try await service.ensureAuthenticated()
        #expect(token1 == initialSession.jwt)

        // Now reauthenticate
        let token2 = try await service.reauthenticate(reason: .unauthorized)
        #expect(token2 != initialSession.jwt)
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

        let networkClient = makeNetworkClient(signInResult: makeSignInResult())

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
        let networkClient = makeNetworkClient(signInResult: makeSignInResult())

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
        let networkClient = makeNetworkClient(signInResult: makeSignInResult())

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
        networkClient.mockSignInResult = makeSignInResult()
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

    // MARK: - D1 Migration Tests (decode-failure vs operational-failure)

    @Test("V1 (old-shape) AuthSession JSON fails to decode")
    func v1JSONDecodeFails() throws {
        // The pre-#351 AuthSession had a single `token` field instead of
        // separate sessionToken + jwt. Verify that the decoder rejects that
        // shape — this is the trigger for the migration path in
        // KeychainTokenStorage.load() (which wraps the throw as
        // keychainError(status: errSecDecode)).
        let v1JSON = """
        {
            "token": "v1-flat-token",
            "userId": "v1-user",
            "createdAt": 0,
            "expiresAt": null
        }
        """.data(using: .utf8)!

        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(AuthSession.self, from: v1JSON)
        }
    }

    @Test("Decode-failure on storage load triggers silent re-sign-in")
    func decodeFailureSilentReauth() async throws {
        let storage = MockThrowingTokenStorage(
            loadError: AuthenticationError.keychainError(status: errSecDecode)
        )
        let freshSession = makeSignInResult()
        let networkClient = makeNetworkClient(signInResult: freshSession)

        let service = makeService(storage: storage, networkClient: networkClient)
        mockAnalytics.reset()

        let token = try await service.ensureAuthenticated()

        // Sign-in happened (decode-failure → re-sign-in)
        #expect(networkClient.signInCallCount == 1)
        #expect(token.contains("."))

        // CRITICAL: no operational-failure event for the decode case. The
        // keychain-decode-error event fires inside KeychainTokenStorage.load()
        // (not exercised here since we mock storage) — the catch arm in
        // ensureAuthenticated() deliberately suppresses RequestLineAuthFailedEvent
        // so ops can tell migration churn apart from real Keychain trouble.
        let failedEvents = mockAnalytics.typedEvents(ofType: RequestLineAuthFailedEvent.self)
            .filter { $0.phase == .keychain }
        #expect(failedEvents.isEmpty)
    }

    @Test("Operational-failure on storage load emits RequestLineAuthFailedEvent")
    func operationalFailureCapturesEvent() async throws {
        let storage = MockThrowingTokenStorage(
            loadError: AuthenticationError.keychainError(status: errSecInteractionNotAllowed)
        )
        let freshSession = makeSignInResult()
        let networkClient = makeNetworkClient(signInResult: freshSession)

        let service = makeService(storage: storage, networkClient: networkClient)
        mockAnalytics.reset()

        _ = try await service.ensureAuthenticated()

        // Sign-in still happens (operational failure → fall-through), but
        // the operational-failure event IS emitted.
        #expect(networkClient.signInCallCount == 1)
        let failedEvents = mockAnalytics.typedEvents(ofType: RequestLineAuthFailedEvent.self)
            .filter { $0.phase == .keychain }
        #expect(failedEvents.count == 1)
    }
}

// MARK: - MockThrowingTokenStorage

/// `TokenStorage` test double whose `load()` always throws the configured
/// error. Used by the D1 migration tests to drive the
/// decode-vs-operational disambiguation in `ensureAuthenticated()`'s catch
/// without standing up a real Keychain (which the SPM unit-test bundle
/// can't access on the simulator due to errSecMissingEntitlement).
private final class MockThrowingTokenStorage: TokenStorage, @unchecked Sendable {
    let loadError: Error
    init(loadError: Error) { self.loadError = loadError }
    func load() throws -> AuthSession? { throw loadError }
    func save(_ session: AuthSession) throws {}
    func delete() throws {}
}

// MARK: - SequentialJWTMock

/// `AuthNetworkClient` that returns a scripted sequence of fetchJWT outcomes
/// so a single test can drive the refresh→401→re-sign-in→success flow.
private final class SequentialJWTMock: AuthNetworkClient, @unchecked Sendable {

    var mockSignInResult: AnonymousSignInResult?
    var fetchJWTOutcomes: [Result<String, Error>] = []

    private(set) var signInCallCount = 0
    private(set) var fetchJWTCallCount = 0
    private let lock = NSLock()

    func signInAnonymously(baseURL: String, deviceFingerprint: String?) async throws -> AnonymousSignInResult {
        lock.withLock { signInCallCount += 1 }
        if let result = mockSignInResult {
            return result
        }
        throw AuthenticationError.networkError(URLError(.notConnectedToInternet))
    }

    func fetchJWT(baseURL: String, sessionToken: String, deviceFingerprint: String?) async throws -> String {
        let outcome: Result<String, Error>? = lock.withLock {
            fetchJWTCallCount += 1
            return fetchJWTOutcomes.isEmpty ? nil : fetchJWTOutcomes.removeFirst()
        }
        switch outcome {
        case .success(let jwt): return jwt
        case .failure(let error): throw error
        case .none:
            throw AuthenticationError.networkError(URLError(.notConnectedToInternet))
        }
    }
}

// MARK: - GatedNetworkMock

/// `AuthNetworkClient` whose `fetchJWT` blocks until `releaseJWT()` is called,
/// so a test can verify concurrent callers share a single in-flight refresh.
private final class GatedNetworkMock: AuthNetworkClient, @unchecked Sendable {

    var mockSignInResult: AnonymousSignInResult?
    var jwtToReturn: String = "gated.jwt.value"
    var gateJWT = false

    private(set) var signInCallCount = 0
    private(set) var fetchJWTCallCount = 0
    private let lock = NSLock()

    // CheckedContinuations used to gate the fetchJWT call. The test calls
    // releaseJWT() to resume them.
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signInAnonymously(baseURL: String, deviceFingerprint: String?) async throws -> AnonymousSignInResult {
        lock.withLock { signInCallCount += 1 }
        guard let result = mockSignInResult else {
            throw AuthenticationError.networkError(URLError(.notConnectedToInternet))
        }
        return result
    }

    func fetchJWT(baseURL: String, sessionToken: String, deviceFingerprint: String?) async throws -> String {
        lock.withLock { fetchJWTCallCount += 1 }

        if gateJWT {
            await withCheckedContinuation { cont in
                lock.withLock { waiters.append(cont) }
            }
        }
        return jwtToReturn
    }

    func releaseJWT() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            let snapshot = waiters
            waiters.removeAll()
            return snapshot
        }
        for cont in pending {
            cont.resume()
        }
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
