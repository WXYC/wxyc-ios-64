//
//  AuthenticationServiceTests.swift
//  ListenerAuth
//
//  Tests for AuthenticationService token management and authentication flow.
//
//  Created by Jake Bromberg on 01/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AnalyticsTesting
import Core
import Foundation
import Security
import Testing
@testable import ListenerAuth

@Suite("AuthenticationService Tests")
struct AuthenticationServiceTests {

    // MARK: - Test Fixtures

    let mockAnalytics = MockStructuredAnalytics()

    func makeService(
        storage: TokenStorage = InMemoryTokenStorage(),
        networkClient: AuthNetworkClient = MockAuthNetworkClient(),
        baseURL: String = "https://api.example.com",
        fingerprintMode: DeviceFingerprintMode = .existing,
        prematureAccessCount: Int = 0
    ) -> AuthenticationService {
        AuthenticationService(
            storage: storage,
            networkClient: networkClient,
            baseURL: baseURL,
            analytics: mockAnalytics,
            fingerprintMode: fingerprintMode,
            prematureAccessCount: prematureAccessCount
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

    // MARK: - #970 set-auth-token is a no-op

    @Test("A set-auth-token header on /auth/token leaves the stored session token and the in-memory cache untouched")
    func mintJWTIgnoresCapturedSessionTokenHeader() async throws {
        let storage = InMemoryTokenStorage()
        let expiredSession = makeExpiredSession()
        try storage.save(expiredSession)

        // jwtExpiresIn short enough that the very next ensureAuthenticated()
        // treats the freshly-minted JWT as stale too, without the test
        // sleeping — same trick saveFailureDegradesToMintNotResignIn uses.
        let networkClient = makeNetworkClient(jwtExpiresIn: 30)
        // A distinct value stands in for better-auth's real
        // set-auth-token — the deterministic HMAC re-encoding of the SAME
        // session token (#970) — so this test would catch persistence being
        // wired back in even against that real shape.
        networkClient.mockCapturedSessionToken = "hmac-reencoded-but-same-credential"

        let service = makeService(storage: storage, networkClient: networkClient)
        _ = try await service.ensureAuthenticated()

        // Storage ("Keychain") still holds the ORIGINAL session token — the
        // header is deliberately ignored (#970).
        #expect(try storage.load()?.sessionToken == expiredSession.sessionToken)
        #expect(networkClient.fetchJWTSessionTokens == [expiredSession.sessionToken])

        // Clear storage so it can no longer supply a session on the next
        // refresh — isolating the in-memory cache as the sole surviving
        // source. THIS is the assertion that fails if anyone re-wires
        // persistence: were `cachedSession` updated from the header, this
        // second mint would send the captured (HMAC-reencoded) value as the
        // session token instead of the original one.
        try storage.delete()

        _ = try await service.ensureAuthenticated()

        #expect(networkClient.fetchJWTSessionTokens == [
            expiredSession.sessionToken,
            expiredSession.sessionToken,
        ])
    }

    @Test("A /auth/token response without a set-auth-token header leaves the stored session token unchanged")
    func mintJWTWithoutHeaderLeavesSessionTokenUnchanged() async throws {
        let storage = InMemoryTokenStorage()
        let expiredSession = makeExpiredSession()
        try storage.save(expiredSession)

        // No mockCapturedSessionToken set — mirrors a response with no
        // set-auth-token header (the common, non-refresh case).
        let networkClient = makeNetworkClient()

        let service = makeService(storage: storage, networkClient: networkClient)
        _ = try await service.ensureAuthenticated()

        #expect(try storage.load()?.sessionToken == expiredSession.sessionToken)
    }

    @Test("A set-auth-token header on the JWT exchange during freshSignIn leaves the persisted and cached session token as the one sign-in returned")
    func freshSignInIgnoresCapturedSessionTokenHeader() async throws {
        let storage = InMemoryTokenStorage()
        // Empty storage — nothing to load, so ensureAuthenticated() takes the
        // freshSignIn() path rather than mintJWT(for:). The other #970 pin
        // above only exercises mintJWT (its pre-seeded storage never reaches
        // freshSignIn), so this covers the sibling leg with the identical
        // ignore-the-header decision at a different call site.
        let signInResult = makeSignInResult()

        // jwtExpiresIn short enough that the very next ensureAuthenticated()
        // treats the freshly-minted JWT as stale too, without the test
        // sleeping — same trick the mintJWT pin above uses.
        let networkClient = makeNetworkClient(signInResult: signInResult, jwtExpiresIn: 30)
        // A distinct value stands in for better-auth's real set-auth-token —
        // the deterministic HMAC re-encoding of the SAME session token
        // (#970) — so this test would catch persistence being wired back in
        // even against that real shape.
        networkClient.mockCapturedSessionToken = "hmac-reencoded-but-same-credential-freshsignin"

        let service = makeService(storage: storage, networkClient: networkClient)
        _ = try await service.ensureAuthenticated()

        // Storage holds the session token sign-in actually returned, not the
        // captured header value.
        #expect(try storage.load()?.sessionToken == signInResult.sessionToken)
        #expect(networkClient.fetchJWTSessionTokens == [signInResult.sessionToken])

        // Clear storage so it can no longer supply a session on the next
        // refresh — isolating the in-memory cache as the sole surviving
        // source. THIS is the assertion that fails if `cachedSession` picked
        // up the captured header instead of signInResult.sessionToken: this
        // second mint would then send the captured value as the session
        // token instead of the one sign-in returned.
        try storage.delete()

        _ = try await service.ensureAuthenticated()

        #expect(networkClient.fetchJWTSessionTokens == [
            signInResult.sessionToken,
            signInResult.sessionToken,
        ])
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

    @Test(
        "Concurrent callers share one in-flight refresh",
        .timeLimit(.minutes(1))
    )
    func concurrentCallersDedup() async throws {
        let storage = InMemoryTokenStorage()
        let networkClient = GatedNetworkMock()
        networkClient.mockSignInResult = makeSignInResult()
        networkClient.gateJWT = true
        let mintedJWT = makeTestJWT()
        networkClient.jwtToReturn = mintedJWT

        let service = makeService(storage: storage, networkClient: networkClient)

        // Spawn the first caller and wait for it to reach the gated fetchJWT.
        // Polling on `waiterCount` instead of a fixed sleep makes this
        // deterministic: when the first waiter is queued in the gate, caller 1
        // has installed `inFlightAuth` on the actor and is suspended inside
        // fetchJWT. Subsequent callers spawned after this point will observe
        // `inFlightAuth` non-nil and take the dedup branch.
        let caller1: Task<String, Error> = Task {
            try await service.ensureAuthenticated()
        }
        while networkClient.waiterCount == 0 {
            await Task.yield()
        }

        // Now spawn the dedup callers. The actor's reentrancy semantics
        // serialize entry; each of these will observe `inFlightAuth` set and
        // await `existing.value` — no second refresh starts.
        let dedupCallers: [Task<String, Error>] = (0..<4).map { _ in
            Task { try await service.ensureAuthenticated() }
        }
        // Yield generously so the dedup callers have a chance to actually
        // reach the actor before we release the gate. If they didn't, the
        // .timeLimit trait above fails the test loudly instead of hanging.
        for _ in 0..<20 { await Task.yield() }

        networkClient.releaseJWT()

        var tokens: [String] = [try await caller1.value]
        for task in dedupCallers {
            tokens.append(try await task.value)
        }

        #expect(tokens.count == 5)
        #expect(tokens.allSatisfy { $0 == mintedJWT })
        // Critical: exactly ONE fetchJWT call, not 5.
        #expect(networkClient.fetchJWTCallCount == 1)
        #expect(networkClient.signInCallCount == 1)
    }

    // MARK: - Device Fingerprint Threading

    @Test("freshSignIn threads a non-nil deviceFingerprint into signInAnonymously and fetchJWT")
    func freshSignInThreadsDeviceFingerprint() async throws {
        // Pin a fingerprint into MusicShareKit's globals. The asserted
        // value is intentionally weaker than `== "specific-uuid"` —
        // AuthenticationServiceTests is not `.serialized`, so a parallel
        // test can reconfigure MusicShareKit between our configure() and
        // the freshSignIn() network reads. The load-bearing claim is
        // "the global is threaded through, not hardcoded to nil," which a
        // non-nil assertion catches without depending on the specific
        // value surviving the race.
        let fingerprintStorage = InMemoryDeviceFingerprintStorage()
        fingerprintStorage.stubFingerprint = "fp-thread-test-\(UUID().uuidString)"
        MusicShareKit.reconfigure(MusicShareKitConfiguration(
            requestOMaticURL: "https://example.com/request",
            authBaseURL: nil,
            keychainAccessGroup: nil,
            featureFlagProvider: nil,
            defaults: UserDefaults.standard,
            analyticsService: mockAnalytics,
            deviceFingerprintStorage: fingerprintStorage
        ))

        let storage = InMemoryTokenStorage()
        let networkClient = makeNetworkClient(signInResult: makeSignInResult())
        let service = makeService(storage: storage, networkClient: networkClient)

        _ = try await service.ensureAuthenticated()

        // CRITICAL: a regression that hardcodes deviceFingerprint: nil in
        // freshSignIn/mintJWT silently disables ban-evasion protection on
        // auth endpoints. Either fingerprint slot being nil catches that.
        #expect(networkClient.signInDeviceFingerprints.allSatisfy { $0 != nil })
        #expect(networkClient.fetchJWTDeviceFingerprints.allSatisfy { $0 != nil })
        #expect(networkClient.signInDeviceFingerprints.count == 1)
        #expect(networkClient.fetchJWTDeviceFingerprints.count == 1)
    }

    @Test("mintJWT threads a non-nil deviceFingerprint into fetchJWT during /auth/token refresh")
    func mintJWTThreadsDeviceFingerprint() async throws {
        // See note in freshSignInThreadsDeviceFingerprint for why the
        // assertion is on non-nil rather than equality.
        let fingerprintStorage = InMemoryDeviceFingerprintStorage()
        fingerprintStorage.stubFingerprint = "fp-mint-test-\(UUID().uuidString)"
        MusicShareKit.reconfigure(MusicShareKitConfiguration(
            requestOMaticURL: "https://example.com/request",
            authBaseURL: nil,
            keychainAccessGroup: nil,
            featureFlagProvider: nil,
            defaults: UserDefaults.standard,
            analyticsService: mockAnalytics,
            deviceFingerprintStorage: fingerprintStorage
        ))

        let storage = InMemoryTokenStorage()
        try storage.save(makeExpiredSession())  // forces /auth/token refresh path

        let networkClient = makeNetworkClient()
        let service = makeService(storage: storage, networkClient: networkClient)

        _ = try await service.ensureAuthenticated()

        // Only fetchJWT is called in the refresh path; signInAnonymously is not.
        #expect(networkClient.signInCallCount == 0)
        #expect(networkClient.fetchJWTDeviceFingerprints.allSatisfy { $0 != nil })
        #expect(networkClient.fetchJWTDeviceFingerprints.count == 1)
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

    @Test("Reauthenticate clears cache and fetches a fresh, server-validated token")
    func reauthenticateClearsCacheAndRefetches() async throws {
        let storage = InMemoryTokenStorage()

        // Initial session (already in storage, bypasses network)
        let initialSession = makeValidSession()
        try storage.save(initialSession)

        let networkClient = makeNetworkClient(signInResult: makeSignInResult())

        let service = makeService(storage: storage, networkClient: networkClient)

        // First, get the initial token (from storage)
        let token1 = try await service.ensureAuthenticated()
        #expect(token1 == initialSession.jwt)

        // Now reauthenticate: the still-valid stored session means recovery
        // is a /auth/token mint (no sign-in), never the rejected JWT back.
        let token2 = try await service.reauthenticate(reason: .unauthorized)
        #expect(token2 != initialSession.jwt)
        #expect(networkClient.signInCallCount == 0)
        #expect(networkClient.fetchJWTCallCount == 1)
    }

    @Test("SessionTokenProvider.reauthenticate(previousToken:) delegates to reauthenticate(reason: .unauthorized) when nothing has refreshed yet")
    func sessionTokenProviderReauthenticateDelegates() async throws {
        let storage = InMemoryTokenStorage()
        let initialSession = makeValidSession()
        try storage.save(initialSession)

        let freshSession = makeSignInResult()
        let networkClient = makeNetworkClient(signInResult: freshSession)

        let tokenProvider: SessionTokenProvider = makeService(storage: storage, networkClient: networkClient)

        let token1 = try await tokenProvider.token()
        #expect(token1 == initialSession.jwt)

        let token2 = try await tokenProvider.reauthenticate(previousToken: token1)
        #expect(token2 != initialSession.jwt)
        // Mint-preserving recovery: no sign-in while the session is valid.
        #expect(networkClient.signInCallCount == 0)
        #expect(networkClient.fetchJWTCallCount == 1)
    }

    @Test("SessionTokenProvider.reauthenticate(previousToken:) short-circuits when the cache already moved past previousToken")
    func sessionTokenProviderReauthenticateShortCircuitsOnStaleToken() async throws {
        let storage = InMemoryTokenStorage()
        let initialSession = makeValidSession()
        try storage.save(initialSession)

        let freshSession = makeSignInResult()
        let networkClient = makeNetworkClient(signInResult: freshSession)

        let service = makeService(storage: storage, networkClient: networkClient)
        let tokenProvider: SessionTokenProvider = service

        // Someone else already recovered from the 401 and refreshed the cache
        // (a mint against the still-valid stored session).
        _ = try await service.reauthenticate(reason: .unauthorized)
        #expect(networkClient.fetchJWTCallCount == 1)

        // A caller that's still holding the OLD (now-superseded) token asks
        // to recover from it — it should get the already-fresh cached JWT
        // straight back, with no second network round trip.
        let token = try await tokenProvider.reauthenticate(previousToken: initialSession.jwt)
        #expect(token != initialSession.jwt)
        #expect(networkClient.signInCallCount == 0, "Must not trigger a redundant sign-in")
        #expect(networkClient.fetchJWTCallCount == 1, "Must not trigger a redundant JWT exchange")
    }

    @Test("Forced reauthentication with a still-valid stored session mints via /auth/token and preserves the session identity")
    func reauthenticatePreservesSessionViaMint() async throws {
        let storage = InMemoryTokenStorage()
        let initialSession = makeValidSession()
        try storage.save(initialSession)

        let networkClient = makeNetworkClient()
        let service = makeService(storage: storage, networkClient: networkClient)

        // Warm the cache with the (about-to-be-rejected) stored JWT.
        let staleToken = try await service.ensureAuthenticated()
        #expect(staleToken == initialSession.jwt)

        let token = try await service.reauthenticate(reason: .unauthorized)

        #expect(token != initialSession.jwt)
        // KEY: recovery from a rejected JWT whose underlying session token is
        // still valid must be a one-round-trip /auth/token mint — NOT a fresh
        // anonymous sign-in, which would change the anonymous userId and
        // orphan the old session server-side.
        #expect(networkClient.signInCallCount == 0)
        #expect(networkClient.fetchJWTCallCount == 1)
        #expect(networkClient.fetchJWTSessionTokens == [initialSession.sessionToken])
        #expect(await service.currentUserId() == initialSession.userId)
    }

    @Test("Forced reauthentication falls back to a fresh sign-in when the mint 401s (session revoked)")
    func reauthenticateFallsBackToSignInWhenMintRejected() async throws {
        let storage = InMemoryTokenStorage()
        let initialSession = makeValidSession()
        try storage.save(initialSession)

        // The mint attempt 401s (session deleted/banned server-side); the
        // post-sign-in mint succeeds.
        let networkClient = SequentialJWTMock()
        networkClient.mockSignInResult = makeSignInResult()
        networkClient.fetchJWTOutcomes = [
            .failure(AuthenticationError.serverError(statusCode: 401)),
            .success(makeTestJWT())
        ]

        let service = makeService(storage: storage, networkClient: networkClient)
        _ = try await service.ensureAuthenticated()

        let token = try await service.reauthenticate(reason: .unauthorized)

        #expect(token.contains("."))
        // Dead session → the existing 401/404 fall-through signs in fresh.
        #expect(networkClient.signInCallCount == 1)
        #expect(networkClient.fetchJWTCallCount == 2)
    }

    @Test("Forced reauthentication on a Keychain-miss device mints from the in-memory session instead of re-signing-in (#948)")
    func reauthenticateOnKeychainMissMintsFromInMemorySession() async throws {
        // Given — the #948 population exactly: storage.save() always throws
        // (a transient -34018), so nothing is ever persisted and load()
        // faithfully returns nil.
        let storage = MockThrowingTokenStorage(
            saveError: AuthenticationError.keychainError(status: errSecInteractionNotAllowed)
        )
        let networkClient = makeNetworkClient()
        let service = makeService(storage: storage, networkClient: networkClient)

        // Nothing stored or cached yet, so this is a legitimate first
        // sign-in. The swallowed save leaves the session in cachedSession
        // only.
        _ = try await service.ensureAuthenticated()
        #expect(networkClient.signInCallCount == 1)
        #expect(networkClient.fetchJWTCallCount == 1)

        // When — the server rejects that JWT and a caller forces a reauth.
        let token = try await service.reauthenticate(reason: .unauthorized)

        // Then — recovery is a one-round-trip /auth/token mint against the
        // rejected session, not a second anonymous sign-in. Without the
        // session being threaded past `reauthenticate`'s cache clear, a
        // Keychain-miss device mints a fresh anonymous DB user on every 401:
        // #948's orphaned-user leak, relocated to the forced-reauth path.
        #expect(token.contains("."))
        #expect(networkClient.signInCallCount == 1, "must not mint a second anonymous user when the in-memory session is still good")
        #expect(networkClient.fetchJWTCallCount == 2, "one mint from the sign-in, one from the recovered mint path")
    }

    /// Characterizes a single `AuthenticationService`: when the Keychain save
    /// throws, the session it signed in for survives in `cachedSession`, so a
    /// later `ensureAuthenticated()` on the same instance answers from that
    /// cache instead of minting a second anonymous user.
    ///
    /// This hand-wires the instance reuse — it never calls `configure(_:)`
    /// and so does not exercise `RunOnceGate`.
    ///
    /// See also `MusicShareKitConfigureGuardTests` for the once-per-process
    /// guard's real coverage, and `saveFailureDegradesToMintNotResignIn`,
    /// which exercises this same fixture more strongly.
    @Test("Reusing one AuthenticationService across two ensureAuthenticated() calls avoids a second sign-in on a Keychain-miss device (#956)")
    func reusingServiceAcrossPresentationsAvoidsDuplicateSignIn() async throws {
        // Given — the #948 population exactly: storage.save() always throws,
        // so nothing is ever persisted and load() faithfully returns nil.
        let storage = MockThrowingTokenStorage(
            saveError: AuthenticationError.keychainError(status: errSecInteractionNotAllowed)
        )
        let networkClient = makeNetworkClient()
        let service = makeService(storage: storage, networkClient: networkClient)

        _ = try await service.ensureAuthenticated()
        #expect(networkClient.signInCallCount == 1)

        _ = try await service.ensureAuthenticated()
        #expect(networkClient.signInCallCount == 1, "a second presentation reusing the same AuthenticationService must not mint a second anonymous user")
    }

    // MARK: - Concurrent reauthenticate Coalescing (H1, #414/#415)

    /// Regression guard for the On-Tour-tab-spins-forever bug: a burst of
    /// concurrent authed calls (playlist artwork, On Tour fetch, etc. on a
    /// cold launch) that all discover the same cached JWT is server-side
    /// rejected must produce exactly ONE fresh sign-in, and every caller
    /// must receive that fresh token — none should see a spurious
    /// `CancellationError` just because another caller's recovery ran
    /// first. Before this fix, `reauthenticate(reason:)` cancelled
    /// `inFlightAuth` and restarted, so concurrent callers raced to cancel
    /// each other; only the last one survived; the rest threw
    /// `CancellationError`, which `OnTourModel.performLoad()` swallows
    /// while `.loading`, leaving the tab spinning forever.
    @Test(
        "A burst of concurrent 401 recoveries for the same rejected token coalesces onto one network refresh; every caller gets the fresh token",
        .timeLimit(.minutes(1))
    )
    func concurrentReauthenticateCoalescesOntoOneSignIn() async throws {
        let storage = InMemoryTokenStorage()
        let initialSession = makeValidSession()
        try storage.save(initialSession)

        let networkClient = GatedNetworkMock()
        networkClient.mockSignInResult = makeSignInResult()
        networkClient.gateJWT = true
        let mintedJWT = makeTestJWT()
        networkClient.jwtToReturn = mintedJWT

        let service = makeService(storage: storage, networkClient: networkClient)
        let tokenProvider: SessionTokenProvider = service

        // Warm the cache so every caller below is recovering from the exact
        // same rejected token, mirroring a cold-launch burst that all fired
        // with the one cached (but server-rejected) JWT.
        let staleToken = try await service.ensureAuthenticated()
        #expect(staleToken == initialSession.jwt)

        let callerCount = 5
        let callers: [Task<String, Error>] = (0..<callerCount).map { _ in
            Task { try await tokenProvider.reauthenticate(previousToken: staleToken) }
        }

        // Wait for the race to settle at the gate, then confirm only ONE
        // caller reached the network — the rest coalesced onto it instead
        // of each independently starting (and cancelling) a sign-in.
        while networkClient.waiterCount == 0 {
            await Task.yield()
        }
        for _ in 0..<20 { await Task.yield() }
        #expect(networkClient.waiterCount == 1)

        networkClient.releaseJWT()

        var tokens: [String] = []
        for task in callers {
            tokens.append(try await task.value)
        }

        #expect(tokens.count == callerCount)
        #expect(tokens.allSatisfy { $0 == mintedJWT }, "Every caller must receive the fresh token, not throw CancellationError")
        // Critical: exactly one JWT exchange, not `callerCount` — and the
        // still-valid stored session means recovery is a mint, so no
        // sign-in (and no new anonymous user) at all.
        #expect(networkClient.signInCallCount == 0)
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

    // MARK: - Analytics Tests (#1067 collapse)

    /// #1067 collapsed `request_line_auth_started_event` +
    /// `request_line_jwt_exchange_event` + `fingerprint_mode_resolved_event`
    /// + `request_line_auth_completed_event` into one
    /// `request_line_auth_resolved` summary per resolution. A fresh sign-in
    /// (3c) is a network resolution with a real JWT exchange, so it must
    /// carry a non-nil `jwtDurationMs`.
    @Test("A fresh sign-in resolution emits exactly one RequestLineAuthResolvedEvent, outcome .freshSignIn")
    func tracksResolvedEventOnFreshSignIn() async throws {
        let storage = InMemoryTokenStorage()
        let networkClient = makeNetworkClient(signInResult: makeSignInResult())

        let service = makeService(
            storage: storage,
            networkClient: networkClient,
            fingerprintMode: .synchronizable,
            prematureAccessCount: 3
        )
        mockAnalytics.reset()

        _ = try await service.ensureAuthenticated()

        // Exactly one event, and it's the resolved summary — not any of the
        // four collapsed names (which no longer exist as types to emit).
        #expect(mockAnalytics.capturedEventNames() == ["request_line_auth_resolved"])

        let resolved = try #require(mockAnalytics.typedEvents(ofType: RequestLineAuthResolvedEvent.self).first)
        #expect(resolved.outcome == .freshSignIn)
        #expect(resolved.fingerprintMode == .synchronizable)
        #expect(resolved.prematureAccessCount == 3)
        #expect(resolved.jwtDurationMs != nil)
        #expect(resolved.durationMs >= 0)
        #expect(resolved.durationClamped == false)
    }

    /// The `/auth/token` mint path (3b) is also a network resolution with a
    /// real JWT exchange, but a distinct outcome from a fresh sign-in — the
    /// distinction #1067's investigation found invisible in the old events
    /// (both bucketed as `source: "network"` with no way to tell them apart).
    @Test("A token-refresh resolution emits exactly one RequestLineAuthResolvedEvent, outcome .tokenRefresh")
    func tracksResolvedEventOnTokenRefresh() async throws {
        let storage = InMemoryTokenStorage()
        let expiredSession = makeExpiredSession()
        try storage.save(expiredSession)
        let networkClient = makeNetworkClient()

        let service = makeService(storage: storage, networkClient: networkClient, fingerprintMode: .local)
        mockAnalytics.reset()

        _ = try await service.ensureAuthenticated()

        #expect(mockAnalytics.capturedEventNames() == ["request_line_auth_resolved"])

        let resolved = try #require(mockAnalytics.typedEvents(ofType: RequestLineAuthResolvedEvent.self).first)
        #expect(resolved.outcome == .tokenRefresh)
        #expect(resolved.fingerprintMode == .local)
        #expect(resolved.jwtDurationMs != nil)
    }

    /// The Keychain-hit path (3a) never calls `/auth/token`, so it must not
    /// claim a JWT exchange duration it didn't measure — `jwtDurationMs` is
    /// `nil`, not `0`, distinguishing "no exchange happened" from "the
    /// exchange somehow took no time."
    @Test("A Keychain-hit resolution emits exactly one RequestLineAuthResolvedEvent with a nil jwtDurationMs")
    func tracksResolvedEventOnKeychainHit() async throws {
        let storage = InMemoryTokenStorage()
        let networkClient = MockAuthNetworkClient()
        let session = makeValidSession()
        try storage.save(session)

        let service = makeService(storage: storage, networkClient: networkClient, fingerprintMode: .existing)
        mockAnalytics.reset()

        // Nothing cached yet, so this reaches performRefresh() and loads the
        // still-fresh session from storage — the 3a branch, not the
        // ensureAuthenticated() in-memory cache fast path (PR1), which is
        // only reachable on a SECOND call.
        let token = try await service.ensureAuthenticated()

        #expect(token == session.jwt)
        #expect(mockAnalytics.capturedEventNames() == ["request_line_auth_resolved"])
        #expect(networkClient.signInCallCount == 0)
        #expect(networkClient.fetchJWTCallCount == 0)

        let resolved = try #require(mockAnalytics.typedEvents(ofType: RequestLineAuthResolvedEvent.self).first)
        #expect(resolved.outcome == .keychainHit)
        #expect(resolved.fingerprintMode == .existing)
        #expect(resolved.jwtDurationMs == nil)
    }

    /// Failure-path visibility is load-bearing for #996/#1002: a resolution
    /// that throws must still emit `RequestLineAuthFailedEvent` unchanged,
    /// and must NOT also emit a resolved summary — "Success path emits one
    /// summary event per resolution" per #1067's acceptance criteria implies
    /// the failure path emits none.
    @Test("A failed resolution emits RequestLineAuthFailedEvent and no RequestLineAuthResolvedEvent")
    func noResolvedEventOnFailure() async throws {
        let storage = InMemoryTokenStorage()
        let networkClient = MockAuthNetworkClient()
        networkClient.mockError = AuthenticationError.networkError(URLError(.notConnectedToInternet))

        let service = makeService(storage: storage, networkClient: networkClient)
        mockAnalytics.reset()

        do {
            _ = try await service.ensureAuthenticated()
            Issue.record("Expected ensureAuthenticated() to throw")
        } catch {
            // Expected.
        }

        #expect(mockAnalytics.typedEvents(ofType: RequestLineAuthFailedEvent.self).count == 1)
        #expect(mockAnalytics.typedEvents(ofType: RequestLineAuthResolvedEvent.self).isEmpty)
        #expect(!mockAnalytics.capturedEventNames().contains("request_line_auth_resolved"))
    }

    /// Regression guard for the four collapsed event names (#1067):
    /// `request_line_auth_started_event`, `request_line_jwt_exchange_event`,
    /// `fingerprint_mode_resolved_event`, and
    /// `request_line_auth_completed_event` no longer exist as types, so this
    /// is largely a compile-time guarantee already — but pinning the exact
    /// name strings here means a future re-introduction under one of these
    /// names (e.g. a hand-rolled `analytics.capture` bypassing the removed
    /// types) still fails loudly instead of silently reinflating the
    /// cluster.
    @Test("No standalone started/jwt-exchange/fingerprint-mode/completed events are emitted across cache, keychain, and network resolutions")
    func noStandaloneLegacyEventsAcrossResolutionKinds() async throws {
        let legacyNames: Set<String> = [
            "request_line_auth_started_event",
            "request_line_jwt_exchange_event",
            "fingerprint_mode_resolved_event",
            "request_line_auth_completed_event",
        ]

        let storage = InMemoryTokenStorage()
        let session = makeValidSession()
        try storage.save(session)
        let networkClient = makeNetworkClient(signInResult: makeSignInResult())
        let service = makeService(storage: storage, networkClient: networkClient)
        mockAnalytics.reset()

        // Keychain hit (3a), then in-memory cache hit (PR1's fast path).
        _ = try await service.ensureAuthenticated()
        _ = try await service.ensureAuthenticated()

        // A fresh sign-in on a separate service instance (network resolution).
        let freshService = makeService(networkClient: makeNetworkClient(signInResult: makeSignInResult()))
        _ = try await freshService.ensureAuthenticated()

        let capturedNames = Set(mockAnalytics.capturedEventNames())
        #expect(capturedNames.isDisjoint(with: legacyNames))
    }

    // MARK: - #1067 Duration Clamp

    /// The #1067 investigation found `duration_ms` values up to 8,452,908 ms
    /// (2.35 h) from the app suspending mid-`await`. `AuthenticationService`
    /// has no injected clock, so this pins the pure clamp function directly
    /// rather than trying to fake a 60-second-plus real delay in a unit test.
    @Test(
        "clamp(_:) caps at 60,000 ms and reports whether it clamped",
        arguments: [
            (0.0, 0.0, false),
            (2_953.0, 2_953.0, false),
            (60_000.0, 60_000.0, false),
            (60_000.001, 60_000.0, true),
            (8_452_908.05, 60_000.0, true),
        ]
    )
    func clampCapsAtMaxDuration(_ fixture: (raw: Double, expectedValue: Double, expectedClamped: Bool)) {
        let (value, wasClamped) = AuthenticationService.clamp(fixture.raw)
        #expect(value == fixture.expectedValue)
        #expect(wasClamped == fixture.expectedClamped)
    }

    // MARK: - #1067 Cache Fast Path Emits No Analytics

    /// The in-memory cache hit at the top of `ensureAuthenticated()` used to
    /// call `trackAuthCompleted(source: .cache, success: true)` with
    /// `durationMs` hardcoded to 0 — a pure in-memory read on the request hot
    /// path, not an auth resolution. Per #1067's investigation, this single
    /// call site accounted for 14,966 of 21,428 `auth_completed` rows over
    /// 12 days (69.8% of the cluster's volume, and 100% of the
    /// `auth_completed`-vs-`auth_started` asymmetry the ticket set out to
    /// explain), while also dragging the shared `duration_ms` field's mean
    /// from a true 2,953 ms down to 854 ms with hardcoded zeros. The 2026-09-12
    /// decision comment on #1067 is to delete the capture outright — not
    /// sample it, not fold it into a counter — because zero saved insights or
    /// alerts read it and an in-memory token read was never the thing this
    /// event exists to measure. This test pins the fast path to emitting
    /// nothing at all, so a future change can't quietly reintroduce a
    /// per-request row here.
    @Test("The in-memory cache fast path emits no analytics event")
    func cacheFastPathEmitsNoAnalytics() async throws {
        let storage = InMemoryTokenStorage()
        let session = makeValidSession()
        try storage.save(session)

        let service = makeService(storage: storage)

        // First call loads from storage into the in-memory cache (not the
        // path under test — this just warms `cachedSession`).
        _ = try await service.ensureAuthenticated()
        mockAnalytics.reset()

        // Second call takes the in-memory cache fast path: `cachedSession` is
        // set and not stale, so this returns before touching storage or the
        // network at all.
        let token = try await service.ensureAuthenticated()

        #expect(token == session.jwt)
        #expect(mockAnalytics.capturedEventNames().isEmpty)
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
        let jwtExchangeFailure = failedEvents.first { $0.phase == AuthFailurePhase.jwtExchange.rawValue }
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
            .filter { $0.phase == AuthFailurePhase.keychain.rawValue }
        #expect(failedEvents.isEmpty)
    }

    @Test("A Keychain write failure degrades to an /auth/token mint on the next stale refresh, instead of re-signing-in")
    func saveFailureDegradesToMintNotResignIn() async throws {
        // Given — storage.save() always throws (matches -34018's silent
        // swallow in `freshSignIn()`'s non-rethrowing catch around
        // `storage.save`), so load() faithfully reports nil: nothing was
        // ever actually persisted.
        let storage = MockThrowingTokenStorage(
            saveError: AuthenticationError.keychainError(status: errSecInteractionNotAllowed)
        )
        // A JWT that expires inside the 60s freshness margin makes the very
        // next ensureAuthenticated() call treat the cached session as stale
        // without the test needing to sleep.
        let networkClient = makeNetworkClient(jwtExpiresIn: 30)

        let service = makeService(storage: storage, networkClient: networkClient)

        // First call: no cached/stored session -> freshSignIn(). storage.save
        // throws and is swallowed, but per the ticket's verified premise,
        // cachedSession is still populated — `freshSignIn()` assigns it
        // after the non-rethrowing catch around storage.save, not before.
        _ = try await service.ensureAuthenticated()
        #expect(networkClient.signInCallCount == 1)

        // Second call: the cached JWT is inside the freshness margin, and the
        // Keychain is still empty. The refresh must recover the in-memory
        // session and mint from it rather than starting a new anonymous
        // identity — escalating to freshSignIn() here is the #948 wedge.
        let token2 = try await service.ensureAuthenticated()
        #expect(networkClient.signInCallCount == 1, "must not re-sign-in on a Keychain miss when cachedSession still holds a good session")
        #expect(networkClient.fetchJWTCallCount == 2, "one mint from freshSignIn, one from the recovered mint path")
        #expect(token2.contains("."))
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
            .filter { $0.phase == AuthFailurePhase.keychain.rawValue }
        #expect(failedEvents.count == 1)
    }
}

// MARK: - MockThrowingTokenStorage

/// `TokenStorage` test double whose `load()` and `save()` can each be
/// independently configured to throw; `load()` otherwise returns nil.
/// Avoids standing up a real Keychain, which the SPM unit-test bundle can't
/// access on the simulator (errSecMissingEntitlement).
private final class MockThrowingTokenStorage: TokenStorage, @unchecked Sendable {
    let loadError: Error?
    let saveError: Error?
    init(loadError: Error? = nil, saveError: Error? = nil) {
        self.loadError = loadError
        self.saveError = saveError
    }
    func load() throws -> AuthSession? {
        if let loadError { throw loadError }
        return nil
    }
    func save(_ session: AuthSession) throws {
        if let saveError { throw saveError }
    }
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

    func fetchJWT(baseURL: String, sessionToken: String, deviceFingerprint: String?) async throws -> JWTExchangeResult {
        let outcome: Result<String, Error>? = lock.withLock {
            fetchJWTCallCount += 1
            return fetchJWTOutcomes.isEmpty ? nil : fetchJWTOutcomes.removeFirst()
        }
        switch outcome {
        case .success(let jwt): return JWTExchangeResult(jwt: jwt)
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

    /// Number of fetchJWT calls currently suspended on the gate.
    var waiterCount: Int { lock.withLock { waiters.count } }

    func signInAnonymously(baseURL: String, deviceFingerprint: String?) async throws -> AnonymousSignInResult {
        lock.withLock { signInCallCount += 1 }
        guard let result = mockSignInResult else {
            throw AuthenticationError.networkError(URLError(.notConnectedToInternet))
        }
        return result
    }

    func fetchJWT(baseURL: String, sessionToken: String, deviceFingerprint: String?) async throws -> JWTExchangeResult {
        lock.withLock { fetchJWTCallCount += 1 }

        if gateJWT {
            await withCheckedContinuation { cont in
                lock.withLock { waiters.append(cont) }
            }
        }
        return JWTExchangeResult(jwt: jwtToReturn)
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
