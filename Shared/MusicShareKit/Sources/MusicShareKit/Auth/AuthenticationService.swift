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

    /// How this process's device fingerprint resolved at
    /// `MusicShareKit.reconfigure(_:)` time — fixed at construction since
    /// resolution happens once, before this instance exists. Reported as
    /// `fingerprint_mode` on every ``RequestLineAuthResolvedEvent`` this
    /// instance emits, replacing the once-per-launch
    /// `fingerprint_mode_resolved_event` (#998) that used to carry it (#1067).
    ///
    /// `internal` rather than `private` for one reason: it is how
    /// `DeviceFingerprintConfigurationTests` checks that `reconfigure(_:)`
    /// actually hands the mode it just computed to the service it builds.
    /// `reconfigure(_:)` wires a real `KeychainTokenStorage` and
    /// `DefaultAuthNetworkClient`, so that suite cannot drive a resolution and
    /// read the mode off the emitted event without touching the Keychain or
    /// the network. Reading the property the constructor actually stored is
    /// the closest observation to the wiring under test — a mirror of the
    /// value published elsewhere would keep passing if the argument here were
    /// changed to a literal.
    let fingerprintMode: DeviceFingerprintMode

    /// Pre-`configure(...)` fingerprint reads counted by `MusicShareKit`,
    /// snapshotted at the same moment as ``fingerprintMode``. Reported as
    /// `premature_access_count`; see that property on
    /// ``RequestLineAuthResolvedEvent`` for what it means and why it rides
    /// here.
    ///
    /// Snapshotted rather than read live at capture time so a resolution's
    /// row states what was true when the service was built, and so this actor
    /// keeps one fewer read of `MusicShareKit`'s mutable globals. The two
    /// agree in practice — the counter can only advance while
    /// `_configuration` is nil, which by construction is before this
    /// instance exists.
    private let prematureAccessCount: Int

    // MARK: - State

    /// In-memory cached session for fast access.
    private var cachedSession: AuthSession?

    /// The in-flight authentication Task, used to deduplicate concurrent
    /// callers (D5 in the iOS#351 plan).
    private var inFlightAuth: Task<String, Error>?

    /// Refresh proactively when the JWT is this close to its `exp`.
    /// 60 s of margin against a ≥15-minute JWT is ~6.7% conservatism.
    private static let freshnessMargin: TimeInterval = 60

    /// Cap applied to every duration reaching ``RequestLineAuthResolvedEvent``
    /// (#1067): `startTime`/`jwtStartTime` are `CFAbsoluteTime` snapshots
    /// taken before an `await`, and the app suspending mid-`await` (e.g.
    /// backgrounded mid-refresh) produced a `duration_ms` as high as
    /// 8,452,908 ms (2.35 h) in the investigation. 60 s is comfortably above
    /// any real auth latency and below "the process was suspended" — see
    /// ``clamp(_:)``.
    private static let maxDurationMs: Double = 60_000

    // MARK: - Initialization

    /// - Parameters:
    ///   - fingerprintMode: What `configure(...)` resolved for this process's
    ///     device fingerprint. Required, with no default, because a default
    ///     would let a future construction site quietly label every one of its
    ///     resolutions with a mode nobody observed.
    ///   - prematureAccessCount: `MusicShareKit.prematureFingerprintAccesses`
    ///     at construction time, required for the same reason.
    public init(
        storage: TokenStorage,
        networkClient: AuthNetworkClient,
        baseURL: String,
        analytics: AnalyticsService,
        fingerprintMode: DeviceFingerprintMode,
        prematureAccessCount: Int
    ) {
        self.storage = storage
        self.networkClient = networkClient
        self.baseURL = baseURL
        self.analytics = analytics
        self.fingerprintMode = fingerprintMode
        self.prematureAccessCount = prematureAccessCount
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
    /// Emits exactly one `RequestLineAuthResolvedEvent` per call (#1067),
    /// named for the branch that actually serves the JWT — `.keychainHit` for
    /// 3a, `.tokenRefresh` for 3b, `.freshSignIn` for 3c. The 401/404
    /// fallthrough is one logical resolution even though it spans both
    /// `/auth/token` and `/sign-in/anonymous`: it reports `.freshSignIn`, the
    /// branch that produced the token, and its `duration_ms` covers both round
    /// trips because `startTime` is taken once, at the top.
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
            cachedSession = session
            trackAuthResolved(outcome: .keychainHit, startTime: startTime, jwtDurationMs: nil)
            return session.jwt
        }

        // 3b. JWT stale but session token might still be valid — refresh via /auth/token.
        if let session = loaded {
            do {
                let (refreshed, jwtDurationMs) = try await mintJWT(for: session)
                trackAuthResolved(outcome: .tokenRefresh, startTime: startTime, jwtDurationMs: jwtDurationMs)
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
        let (session, jwtDurationMs) = try await freshSignIn()
        trackAuthResolved(outcome: .freshSignIn, startTime: startTime, jwtDurationMs: jwtDurationMs)
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
    ///
    /// - Returns: The refreshed session and the raw (unclamped) JWT exchange
    ///   duration, for the caller's ``RequestLineAuthResolvedEvent`` (#1067
    ///   removed this method's own `request_line_jwt_exchange_event` capture).
    private func mintJWT(for session: AuthSession) async throws -> (session: AuthSession, jwtDurationMs: Double) {
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
        let jwtDurationMs = (CFAbsoluteTimeGetCurrent() - jwtStartTime) * 1000

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
        return (refreshed, jwtDurationMs)
    }

    /// Sign in anonymously and mint a fresh JWT for the new session.
    ///
    /// - Returns: The new session and the raw JWT exchange duration — see the
    ///   matching note on ``mintJWT(for:)``.
    private func freshSignIn() async throws -> (session: AuthSession, jwtDurationMs: Double) {
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
        let jwtDurationMs = (CFAbsoluteTimeGetCurrent() - jwtStartTime) * 1000

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
        return (session, jwtDurationMs)
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

    /// Captures one ``RequestLineAuthResolvedEvent`` (#1067). `jwtDurationMs`
    /// is `nil` on `.keychainHit`, where no JWT exchange happens.
    ///
    /// - Parameters:
    ///   - startTime: Taken at the top of ``performRefresh(trustStoredJWT:fallbackSession:)``,
    ///     so the reported total spans every round trip the resolution needed.
    ///   - jwtDurationMs: The raw, unclamped exchange duration; clamped here
    ///     rather than at the measurement site so both durations pass through
    ///     one cap and one `durationClamped` verdict.
    private func trackAuthResolved(
        outcome: AuthResolutionOutcome,
        startTime: CFAbsoluteTime,
        jwtDurationMs: Double?
    ) {
        let total = Self.clamp((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        let jwt = jwtDurationMs.map(Self.clamp)

        analytics.capture(RequestLineAuthResolvedEvent(
            outcome: outcome,
            fingerprintMode: fingerprintMode,
            prematureAccessCount: prematureAccessCount,
            jwtDurationMs: jwt?.value,
            durationMs: total.value,
            durationClamped: total.wasClamped || jwt?.wasClamped == true
        ))
    }

    /// Caps `raw` at ``maxDurationMs`` (see its doc comment for why).
    /// `internal`, not `private`, so tests can exercise this pure function
    /// directly — there's no injected clock, and 60 s is too long to sleep
    /// through in a unit test.
    static func clamp(_ raw: Double) -> (value: Double, wasClamped: Bool) {
        guard raw > maxDurationMs else { return (raw, false) }
        return (maxDurationMs, true)
    }
}
