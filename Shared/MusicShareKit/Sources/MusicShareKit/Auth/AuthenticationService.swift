//
//  AuthenticationService.swift
//  MusicShareKit
//
//  Main actor orchestrating anonymous authentication flow.
//
//  Created by Jake Bromberg on 01/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import Core
import Foundation
import Security

/// Service for managing anonymous authentication.
///
/// Handles JWT caching, session-token-keyed refresh, Keychain persistence,
/// and network sign-in. All operations are serialized on the actor so
/// concurrent callers share a single in-flight refresh.
public actor AuthenticationService: SessionTokenProvider {

    // MARK: - Dependencies

    private let storage: TokenStorage
    private let networkClient: AuthNetworkClient
    private let baseURL: String
    private let analytics: AnalyticsService

    // MARK: - State

    /// In-memory cached session for fast access.
    private var cachedSession: AuthSession?

    /// The in-flight authentication Task, used to deduplicate concurrent
    /// callers (D5 in the iOS#351 plan).
    private var inFlightAuth: Task<String, Error>?

    /// Refresh proactively when the JWT is this close to its `exp`.
    /// 60 s of margin against a ≥15-minute JWT is ~6.7% conservatism.
    private static let freshnessMargin: TimeInterval = 60

    // MARK: - Initialization

    public init(
        storage: TokenStorage,
        networkClient: AuthNetworkClient,
        baseURL: String,
        analytics: AnalyticsService
    ) {
        self.storage = storage
        self.networkClient = networkClient
        self.baseURL = baseURL
        self.analytics = analytics
    }

    // MARK: - Public API

    /// Ensures the user is authenticated and returns a valid JWT.
    ///
    /// Flow (D5 in the iOS#351 plan):
    /// 1. Return cached JWT if not within `freshnessMargin` of expiry.
    /// 2. If another caller already kicked off a refresh, await its result.
    /// 3. Otherwise, kick off a refresh and publish its handle so subsequent
    ///    callers can share the result.
    ///
    /// - Returns: A valid JWT bearer token.
    /// - Throws: `AuthenticationError` if authentication fails.
    public func ensureAuthenticated() async throws -> String {
        // 1. In-memory cache — fast path.
        if let cached = cachedSession, !cached.jwtIsStale(margin: Self.freshnessMargin) {
            trackAuthCompleted(source: .cache, success: true)
            return cached.jwt
        }

        // 2. Concurrent-call dedup — share any in-flight refresh.
        if let existing = inFlightAuth {
            return try await existing.value
        }

        // 3. Start refresh, publish handle BEFORE first await.
        //
        // Cleanup invariant: `inFlightAuth` is cleared by
        // `performRefreshAndClear()`'s `defer`, which runs on the actor before
        // the Task closure returns. The outer caller's catch path does NOT
        // clear `inFlightAuth` — if the outer caller's surrounding Task is
        // cancelled (e.g., view disappears), the await throws
        // `CancellationError` but the refresh Task itself continues running
        // and will clean up its own handle when it completes. This prevents
        // the "cancelled-caller clears handle while refresh is still
        // in-flight, next caller starts a duplicate refresh" race.
        //
        // Reentrancy safety: subsequent `ensureAuthenticated()` callers that
        // enter the actor between `inFlightAuth = task` and the Task's
        // `defer { inFlightAuth = nil }` will see `inFlightAuth != nil` and
        // share the result via the branch above. Actor property writes are
        // atomic between suspension points.
        let task = Task<String, Error> { [weak self] in
            guard let self else { throw AuthenticationError.notConfigured }
            return try await self.performRefreshAndClear()
        }
        inFlightAuth = task
        return try await task.value
    }

    /// Forces reauthentication, clearing cached and stored sessions.
    ///
    /// Currently dead path on the happy-path because ROM strips 401s, but
    /// kept defensively for any future call site (e.g., a manual
    /// "sign out + back in" UI).
    public func reauthenticate(reason: TokenRefreshReason) async throws -> String {
        analytics.capture(RequestLineTokenRefreshedEvent(reason: reason, success: true))

        cachedSession = nil
        do {
            try storage.delete()
        } catch {
            analytics.capture(RequestLineAuthFailedEvent(
                error: error.localizedDescription,
                phase: .keychain
            ))
        }

        return try await ensureAuthenticated()
    }

    /// Returns the current user ID if authenticated.
    public func currentUserId() async -> String? {
        if let session = cachedSession, !session.isExpired {
            return session.userId
        }

        do {
            if let session = try storage.load(), !session.isExpired {
                cachedSession = session
                return session.userId
            }
        } catch {
            // Ignore errors — currentUserId() is best-effort.
        }

        return nil
    }

    /// Clears all authentication state.
    public func signOut() async {
        cachedSession = nil
        try? storage.delete()
    }

    // MARK: - SessionTokenProvider

    /// Conforms to `SessionTokenProvider` so services in Artwork and Metadata
    /// packages can obtain a Bearer token without depending on MusicShareKit.
    public func token() async throws -> String {
        try await ensureAuthenticated()
    }

    // MARK: - Private Refresh Flow

    /// Wraps `performRefresh()` with the cleanup invariant for `inFlightAuth`.
    ///
    /// Actor-isolated, so `defer` runs on the actor's executor at function
    /// exit (success or throw). This is the ONLY site that clears
    /// `inFlightAuth`; the outer `ensureAuthenticated()` body never clears it.
    private func performRefreshAndClear() async throws -> String {
        defer { inFlightAuth = nil }
        return try await performRefresh()
    }

    /// The actual refresh flow: Keychain → `/auth/token` → re-sign-in.
    private func performRefresh() async throws -> String {
        let startTime = CFAbsoluteTimeGetCurrent()

        // 3a. Try Keychain (restored from another process or cold start).
        trackAuthStarted(source: .keychain)
        let loaded = loadFromKeychain()
        if let session = loaded, !session.jwtIsStale(margin: Self.freshnessMargin) {
            cachedSession = session
            trackAuthCompleted(source: .keychain, startTime: startTime, success: true)
            return session.jwt
        }

        // 3b. JWT stale but session token might still be valid — refresh via /auth/token.
        if let session = loaded {
            do {
                let refreshed = try await mintJWT(for: session)
                trackAuthCompleted(source: .network, startTime: startTime, success: true)
                return refreshed.jwt
            } catch AuthenticationError.serverError(statusCode: 401),
                    AuthenticationError.serverError(statusCode: 404) {
                // Session deleted (banned) or expired — fall through to re-sign-in.
                cachedSession = nil
                try? storage.delete()
            }
            // Any other error propagates out (network glitch, malformed JWT,
            // etc.). The caller retries on the next ensureAuthenticated().
        }

        // 3c. No session, or session just nuked — fresh anonymous sign-in.
        trackAuthStarted(source: .network)
        let session = try await freshSignIn()
        trackAuthCompleted(source: .network, startTime: startTime, success: true)
        return session.jwt
    }

    /// Attempts a Keychain load, disambiguating decode-failure (migration)
    /// from operational-failure (locked, denied, etc.) per D1.
    private func loadFromKeychain() -> AuthSession? {
        do {
            return try storage.load()
        } catch AuthenticationError.keychainError(status: errSecDecode) {
            // Migration / data-corruption case — `KeychainTokenStorage.load()`
            // already fired a `keychain-decode-error` event from inside. Silent
            // fall-through to the network sign-in branch. We deliberately do
            // NOT emit the operational-failure event here — the two failure
            // modes get distinct telemetry shapes so ops can tell migration
            // churn apart from real Keychain trouble.
            return nil
        } catch {
            // Operational Keychain failure — locked, denied, missing entitlement.
            analytics.capture(RequestLineAuthFailedEvent(
                error: error.localizedDescription,
                phase: .keychain
            ))
            return nil
        }
    }

    /// Mint a fresh JWT for an existing session via `/auth/token`.
    private func mintJWT(for session: AuthSession) async throws -> AuthSession {
        let jwtStartTime = CFAbsoluteTimeGetCurrent()
        let newJWT: String
        do {
            newJWT = try await networkClient.fetchJWT(
                baseURL: baseURL,
                sessionToken: session.sessionToken,
                deviceFingerprint: MusicShareKit.deviceFingerprint
            )
        } catch {
            analytics.capture(RequestLineAuthFailedEvent(
                error: error.localizedDescription,
                phase: .jwtExchange
            ))
            throw error
        }
        let jwtDuration = (CFAbsoluteTimeGetCurrent() - jwtStartTime) * 1000
        analytics.capture(RequestLineJWTExchangeEvent(success: true, durationMs: jwtDuration))

        let payload = try JWTPayloadDecoder.decode(newJWT)
        let refreshed = session.with(jwt: newJWT, expiresAt: payload.expiresAt)
        try? storage.save(refreshed)
        cachedSession = refreshed
        return refreshed
    }

    /// Sign in anonymously and mint a fresh JWT for the new session.
    private func freshSignIn() async throws -> AuthSession {
        // Read the device fingerprint once so the same value lands on both
        // the sign-in (audit trail) and the JWT fetch (consistency).
        let fingerprint = MusicShareKit.deviceFingerprint

        let signInResult: AnonymousSignInResult
        do {
            signInResult = try await networkClient.signInAnonymously(
                baseURL: baseURL, deviceFingerprint: fingerprint
            )
        } catch {
            analytics.capture(RequestLineAuthFailedEvent(
                error: error.localizedDescription,
                phase: .network
            ))
            throw error
        }

        let jwtStartTime = CFAbsoluteTimeGetCurrent()
        let jwt: String
        do {
            jwt = try await networkClient.fetchJWT(
                baseURL: baseURL,
                sessionToken: signInResult.sessionToken,
                deviceFingerprint: fingerprint
            )
        } catch {
            analytics.capture(RequestLineAuthFailedEvent(
                error: error.localizedDescription,
                phase: .jwtExchange
            ))
            throw error
        }
        let jwtDuration = (CFAbsoluteTimeGetCurrent() - jwtStartTime) * 1000
        analytics.capture(RequestLineJWTExchangeEvent(success: true, durationMs: jwtDuration))

        let payload = try JWTPayloadDecoder.decode(jwt)
        let session = AuthSession(
            sessionToken: signInResult.sessionToken,
            jwt: jwt,
            userId: signInResult.userId,
            createdAt: Date(),
            expiresAt: payload.expiresAt
        )

        do {
            try storage.save(session)
        } catch {
            // Log but don't fail - we have a valid session in memory.
            analytics.capture(RequestLineAuthFailedEvent(
                error: error.localizedDescription,
                phase: .keychain
            ))
        }

        cachedSession = session
        return session
    }

    // MARK: - Analytics

    private func trackAuthStarted(source: AuthTokenSource) {
        analytics.capture(RequestLineAuthStartedEvent(source: source))
    }

    private func trackAuthCompleted(source: AuthTokenSource, success: Bool) {
        analytics.capture(RequestLineAuthCompletedEvent(
            source: source,
            durationMs: 0,
            success: success
        ))
    }

    private func trackAuthCompleted(
        source: AuthTokenSource,
        startTime: CFAbsoluteTime,
        success: Bool
    ) {
        let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        analytics.capture(RequestLineAuthCompletedEvent(
            source: source,
            durationMs: duration,
            success: success
        ))
    }
}
