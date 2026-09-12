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
        //
        // Deliberately emits no analytics (#1067): a pure in-memory read on
        // the request hot path is not an auth resolution. The deleted
        // `trackAuthCompleted(source: .cache, success: true)` call here used
        // to fire on every authed request once the cache warmed, hardcoding
        // `durationMs: 0` — 14,966 of 21,428 `auth_completed` rows over 12
        // days (69.8% of the cluster), and the reason `auth_completed` fired
        // 3.2x more often than `auth_started`. Its zero-duration
        // `trackAuthCompleted` overload went with it: this was the overload's
        // only caller, so leaving it behind would have left a one-call-away
        // reintroduction of the same defect. See the 2026-09-12 decision
        // comment on #1067 for the full accounting.
        if let cached = cachedSession, !cached.jwtIsStale(margin: Self.freshnessMargin) {
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
            guard let self else { throw SessionTokenProviderError.notConfigured }
            return try await self.performRefreshAndClear(trustStoredJWT: true)
        }
        inFlightAuth = task
        return try await task.value
    }

    /// Forces a fresh JWT after the server rejected the current one,
    /// preserving the stored session identity when it is still valid.
    ///
    /// Live, concurrently-invoked path: `RequestService` calls it directly
    /// on a request 401, and every authed call in `Concerts`/`Metadata`
    /// (via `URLSession.authedData(for:tokenProvider:)`) reaches it through
    /// `reauthenticate(previousToken:)` below. A cold launch can fire
    /// several of those at once against the same stale/rejected session, so
    /// this coalesces concurrent callers onto a single in-flight refresh —
    /// sharing `ensureAuthenticated()`'s `inFlightAuth` handle — instead of
    /// each cancelling the last one's work. `performRefresh()`'s 401/404
    /// fall-through means any refresh already in flight, proactive or
    /// forced, converges on a fresh sign-in on its own once it discovers its
    /// session is server-side invalid, so sharing it here is safe even when
    /// it started before this call's caller knew its token was bad. Prior to
    /// this coalescing, forcing a restart here (`inFlightAuth?.cancel()`)
    /// surfaced as `CancellationError` to every other caller sharing that
    /// Task — on a cold launch that's `OnTourModel.performLoad()`, which
    /// swallows cancellation while `.loading`, leaving the On Tour tab
    /// spinning forever (#414/#415).
    ///
    /// The keychain session is deliberately NOT cleared up front: a rejected
    /// JWT usually belongs to a session token that is still valid (benign
    /// expiry, key rotation), which `performRefresh()`'s `/auth/token` mint
    /// recovers in one round trip while preserving the anonymous `userId`.
    /// Wiping first would foreclose that branch and force a full anonymous
    /// sign-in — a second network round trip plus one more orphaned
    /// server-side anonymous user per benign 401. When this call starts its
    /// own refresh, skipping the client-side-freshness fast paths
    /// (`trustStoredJWT: false`) keeps the rejected token from being handed
    /// straight back — the cache is cleared and the keychain copy is
    /// distrusted, so the refresh must produce a server-validated JWT. A
    /// genuinely dead session still converges on `freshSignIn()` via the
    /// mint's 401/404 fall-through.
    ///
    /// That freshness skip does NOT extend to the coalescing branch below.
    /// A caller arriving while an `ensureAuthenticated()` refresh
    /// (`trustStoredJWT: true`) is already in flight shares that Task's
    /// result — which, if that refresh takes the keychain fast path on a
    /// client-fresh-but-server-rejected JWT, can be the rejected token
    /// itself. The caller's single retry then 401s and that one fetch fails;
    /// the NEXT call passes the rejected JWT as `previousToken`, takes the
    /// mint path, and recovers. Same self-healing trade-off documented on
    /// `reauthenticate(previousToken:)`.
    public func reauthenticate(reason: TokenRefreshReason) async throws -> String {
        if let existing = inFlightAuth {
            return try await existing.value
        }

        // Clear only the in-memory cache; the stored session must survive so
        // performRefresh() can attempt the identity-preserving mint. On a
        // device whose Keychain writes are failing there is no stored copy,
        // so hand the rejected session to performRefresh explicitly — what
        // the server rejected is the JWT, not the ~7-day session token under
        // it (#948).
        let rejectedSession = cachedSession
        cachedSession = nil

        let task = Task<String, Error> { [weak self] in
            guard let self else { throw SessionTokenProviderError.notConfigured }
            return try await self.performRefreshAndClear(
                trustStoredJWT: false,
                fallbackSession: rejectedSession
            )
        }
        inFlightAuth = task

        do {
            let token = try await task.value
            analytics.capture(RequestLineTokenRefreshedEvent(reason: reason, success: true))
            return token
        } catch {
            // Emit success=false so dashboards distinguish "reauth attempted
            // and succeeded" from "reauth attempted and hard-failed".
            analytics.capture(RequestLineTokenRefreshedEvent(reason: reason, success: false))
            throw error
        }
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
        // Cancel any in-flight refresh and clear the dedup handle — otherwise
        // a Task still running at sign-out time would write a fresh session
        // into cachedSession + Keychain after we return, silently
        // re-authenticating the just-signed-out user.
        inFlightAuth?.cancel()
        inFlightAuth = nil

        cachedSession = nil
        try? storage.delete()
    }

    // MARK: - SessionTokenProvider

    /// Conforms to `SessionTokenProvider` so services in Artwork, Concerts,
    /// and Metadata packages can obtain a Bearer token without depending on
    /// MusicShareKit.
    public func token() async throws -> String {
        try await ensureAuthenticated()
    }

    /// Forces a fresh session token after `previousToken` was rejected, for
    /// `SessionTokenProvider` conformance.
    ///
    /// Short-circuits when another concurrent caller already refreshed past
    /// `previousToken` — `cachedSession` holds a different, still-fresh JWT
    /// — handing it back directly with no network call and nothing to
    /// coalesce onto. Otherwise delegates to ``reauthenticate(reason:)``
    /// with `.unauthorized`, which coalesces concurrent forced-refreshes
    /// onto a single in-flight refresh; see its doc for the full concurrency
    /// contract this satisfies.
    ///
    /// Accepted trade-off: the short-circuit judges freshness client-side
    /// only. In the narrow race where a proactive refresh minted a newer JWT
    /// from the same session and the server then revoked that whole session,
    /// the newer JWT is handed back unvalidated, the caller's single retry
    /// 401s, and that one fetch fails — the NEXT call passes the newer JWT
    /// as `previousToken`, takes the full path, and recovers. Self-healing
    /// within one request, and strictly better than pre-#716 (no recovery
    /// at all), so we prefer it over paying a validation round trip on every
    /// short-circuit.
    public func reauthenticate(previousToken: String) async throws -> String {
        if let cachedSession,
           cachedSession.jwt != previousToken,
           !cachedSession.jwtIsStale(margin: Self.freshnessMargin) {
            return cachedSession.jwt
        }
        return try await reauthenticate(reason: .unauthorized)
    }

    // MARK: - Private Refresh Flow

    /// Wraps `performRefresh(trustStoredJWT:)` with the cleanup invariant for
    /// `inFlightAuth`.
    ///
    /// Actor-isolated, so `defer` runs on the actor's executor at function
    /// exit (success or throw). This is the ONLY site that clears
    /// `inFlightAuth`; the outer `ensureAuthenticated()` body never clears it.
    private func performRefreshAndClear(
        trustStoredJWT: Bool,
        fallbackSession: AuthSession? = nil
    ) async throws -> String {
        defer { inFlightAuth = nil }
        return try await performRefresh(
            trustStoredJWT: trustStoredJWT,
            fallbackSession: fallbackSession
        )
    }

    /// The actual refresh flow: Keychain → `/auth/token` → re-sign-in.
    ///
    /// - Parameter trustStoredJWT: When `false` (a forced reauthentication —
    ///   the server just rejected a JWT that may look fresh client-side),
    ///   the keychain fast path (3a) is skipped so the flow always produces
    ///   a server-validated JWT: a `/auth/token` mint when the stored
    ///   session token is still valid, else a fresh sign-in.
    ///
    /// Emits exactly one matched `RequestLineAuthStartedEvent` /
    /// `RequestLineAuthCompletedEvent` pair per call, sourced from the
    /// branch that actually serves the JWT. The 401/404 fallthrough is a
    /// single logical "network" auth even though it spans both
    /// `/auth/token` and `/sign-in/anonymous`.
    ///
    /// - Parameter fallbackSession: A session the caller is holding that is
    ///   not in `cachedSession` — currently only
    ///   ``reauthenticate(reason:)``, which clears the cache before
    ///   refreshing and would otherwise drop the last in-memory copy on a
    ///   device whose Keychain writes are failing (#948).
    private func performRefresh(
        trustStoredJWT: Bool,
        fallbackSession: AuthSession?
    ) async throws -> String {
        let startTime = CFAbsoluteTimeGetCurrent()
        // A Keychain miss is not proof there is no session: `freshSignIn()`
        // and `mintJWT(for:)` both swallow a failing `storage.save`, so an
        // in-memory session whose *session token* is good for ~7 days can
        // outlive a Keychain that never persisted it. Escalating straight to
        // `freshSignIn()` in that state is what wedges anonymous auth (#948).
        let loaded = loadFromKeychain() ?? fallbackSession ?? cachedSession

        // 3a. Keychain hit on a fresh JWT — fast path.
        if trustStoredJWT, let session = loaded, !session.jwtIsStale(margin: Self.freshnessMargin) {
            trackAuthStarted(source: .keychain)
            cachedSession = session
            trackAuthCompleted(source: .keychain, startTime: startTime, success: true)
            return session.jwt
        }

        trackAuthStarted(source: .network)

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
        let minted: JWTExchangeResult
        do {
            minted = try await networkClient.fetchJWT(
                baseURL: baseURL,
                sessionToken: session.sessionToken,
                deviceFingerprint: MusicShareKit.deviceFingerprint
            )
        } catch let error as AuthenticationError {
            // Recoverable 401/404 means the session was deleted (banned) or
            // expired server-side. performRefresh's catch arm falls through
            // to freshSignIn() — this is the intended ban-recovery path, not
            // a true exchange failure, so don't pollute the auth-failed
            // funnel with it.
            if case .serverError(statusCode: 401) = error { throw error }
            if case .serverError(statusCode: 404) = error { throw error }
            // signOut/reauthenticate cancellation surfaces as URLError.cancelled
            // wrapped in AuthenticationError.networkError. The user-initiated
            // sign-out should not look like a transient exchange failure in
            // the funnel.
            if isCancellationError(error) { throw error }
            analytics.capture(RequestLineAuthFailedEvent(
                error: error.localizedDescription,
                phase: .jwtExchange
            ))
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            analytics.capture(RequestLineAuthFailedEvent(
                error: error.localizedDescription,
                phase: .jwtExchange
            ))
            throw error
        }

        // If signOut/reauthenticate cancelled us between the await above and
        // here, exit before persisting — otherwise we'd resurrect the just-
        // cleared state. Awaiters of this Task see CancellationError; that
        // matches the user's intent in calling signOut.
        try Task.checkCancellation()

        let payload = try JWTPayloadDecoder.decode(minted.jwt)
        let jwtDuration = (CFAbsoluteTimeGetCurrent() - jwtStartTime) * 1000
        analytics.capture(RequestLineJWTExchangeEvent(success: true, durationMs: jwtDuration))

        // `minted.capturedSessionToken` is deliberately ignored: better-auth
        // 1.6.30 never rewrites a session's token value, so there is nothing
        // to persist here. See `JWTExchangeResult`'s doc comment and issue
        // #970's decision comment for the verified mechanism.
        let refreshed = session.with(jwt: minted.jwt, expiresAt: payload.expiresAt)
        do {
            try storage.save(refreshed)
        } catch {
            analytics.capture(RequestLineAuthFailedEvent(
                error: error.localizedDescription,
                phase: .keychain
            ))
        }
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
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Treat signOut/reauthenticate cancellation as not-an-auth-failure.
            if isCancellationError(error) { throw error }
            analytics.capture(RequestLineAuthFailedEvent(
                error: error.localizedDescription,
                phase: .network
            ))
            throw error
        }

        let jwtStartTime = CFAbsoluteTimeGetCurrent()
        let minted: JWTExchangeResult
        do {
            minted = try await networkClient.fetchJWT(
                baseURL: baseURL,
                sessionToken: signInResult.sessionToken,
                deviceFingerprint: fingerprint
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if isCancellationError(error) { throw error }
            analytics.capture(RequestLineAuthFailedEvent(
                error: error.localizedDescription,
                phase: .jwtExchange
            ))
            throw error
        }

        // Bail before persisting if signOut/reauthenticate cancelled us; see
        // the matching check in mintJWT for the rationale.
        try Task.checkCancellation()

        let payload = try JWTPayloadDecoder.decode(minted.jwt)
        let jwtDuration = (CFAbsoluteTimeGetCurrent() - jwtStartTime) * 1000
        analytics.capture(RequestLineJWTExchangeEvent(success: true, durationMs: jwtDuration))

        // `minted.capturedSessionToken` is deliberately ignored here too —
        // same rationale as `mintJWT` above.
        let session = AuthSession(
            sessionToken: signInResult.sessionToken,
            jwt: minted.jwt,
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

    // MARK: - Helpers

    /// True when `error` is a Task / URLSession cancellation surfaced through
    /// the auth-network layer. Used by the catch arms in `mintJWT` and
    /// `freshSignIn` so a user-initiated signOut/reauthenticate that
    /// interrupts an in-flight refresh isn't reported as an auth failure.
    private nonisolated func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if case AuthenticationError.networkError(let underlying) = error {
            if underlying is CancellationError { return true }
            if let urlError = underlying as? URLError, urlError.code == .cancelled {
                return true
            }
        }
        return false
    }

    // MARK: - Analytics

    private func trackAuthStarted(source: AuthTokenSource) {
        analytics.capture(RequestLineAuthStartedEvent(source: source))
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
