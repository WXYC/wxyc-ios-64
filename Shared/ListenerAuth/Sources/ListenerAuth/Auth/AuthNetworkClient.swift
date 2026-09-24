//
//  AuthNetworkClient.swift
//  ListenerAuth
//
//  Protocol and default implementation for authentication network requests.
//
//  Created by Jake Bromberg on 01/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Core
import Foundation

/// Protocol for making authentication network requests.
///
/// Allows mocking the network layer in tests.
public protocol AuthNetworkClient: Sendable {

    /// Signs in anonymously and returns the session token + assigned user id.
    ///
    /// The JWT is NOT minted here — fetch one via `fetchJWT(baseURL:sessionToken:deviceFingerprint:)`
    /// using the returned session token.
    ///
    /// - Parameters:
    ///   - baseURL: The base URL for the authentication API.
    ///   - deviceFingerprint: The stable per-device UUID to send as
    ///     `X-Device-Fingerprint` so BS can associate the fingerprint with
    ///     the freshly-minted user.id at sign-in time. Pass `nil` to omit
    ///     the header (audit-trail data missing, request still succeeds).
    /// - Returns: The session token and user id for the new anonymous account.
    /// - Throws: `AuthenticationError` if the sign-in fails, or
    ///   `SessionTokenProviderError.notConfigured` if `baseURL` is malformed.
    func signInAnonymously(
        baseURL: String, deviceFingerprint: String?
    ) async throws -> AnonymousSignInResult

    /// Exchanges a session token for a JWT.
    ///
    /// - Parameters:
    ///   - baseURL: The base URL for the authentication API.
    ///   - sessionToken: The session token from anonymous sign-in.
    ///   - deviceFingerprint: Stable per-device UUID for the audit-trail
    ///     header. Pass `nil` to omit.
    /// - Returns: The minted JWT, plus the raw `set-auth-token` header value
    ///   the response carried, if any (#970).
    /// - Throws: `AuthenticationError` if the exchange fails, or
    ///   `SessionTokenProviderError.notConfigured` if `baseURL` is malformed.
    func fetchJWT(
        baseURL: String, sessionToken: String, deviceFingerprint: String?
    ) async throws -> JWTExchangeResult
}

/// Result of a `/auth/token` exchange: the minted JWT, plus whatever
/// `set-auth-token` header value the response carried.
///
/// better-auth's `bearer()` plugin echoes `set-auth-token` on any response
/// that re-issues the session cookie, including `/auth/token` once the
/// session crosses `updateAge`. It reads like a rotation, but isn't one:
/// verified against the better-auth 1.6.30 dist Backend-Service actually
/// loads (`apps/auth/node_modules/better-auth`), the session `token` column
/// is assigned once at `generateId(32)` and never rewritten — `updateSession`
/// (`dist/api/routes/session.mjs`) uses the existing token purely as the
/// lookup key and updates only `expiresAt`/`updatedAt`
/// (`dist/db/internal-adapter.mjs`), and the header itself is a deterministic
/// `HMAC(token, secret)` re-encoding of that same, unchanged token
/// (`dist/cookies/index.mjs`) — not a new credential. `capturedSessionToken`
/// exists so `DefaultAuthNetworkClient` has somewhere to put the header it
/// read (and a real surface to test), but it is not a signal any caller
/// should act on. See `AuthenticationService`'s doc comment where it's
/// received and deliberately ignored, and issue #970's decision comment:
/// https://github.com/WXYC/wxyc-ios-64/issues/970#issuecomment-5398772782
public struct JWTExchangeResult: Sendable, Equatable {

    /// The freshly-minted JWT bearer token.
    public let jwt: String

    /// The `set-auth-token` header value, when the response carried one.
    /// Deliberately unused by `AuthenticationService` — see the type's doc
    /// comment. This is a raw capture with no normalization: an
    /// empty-valued header surfaces as `""`, not `nil` — only a genuinely
    /// absent header produces `nil` — so a future consumer (the planned
    /// Phase B/D2 work) must not assume `if let capturedSessionToken` alone
    /// rules out an empty string.
    public let capturedSessionToken: String?

    public init(jwt: String, capturedSessionToken: String? = nil) {
        self.jwt = jwt
        self.capturedSessionToken = capturedSessionToken
    }
}

// MARK: - Default Implementation

/// Default implementation of `AuthNetworkClient` using URLSession.
///
/// This is a pure bearer-token client and has no use for a cookie jar, so
/// the session is genuinely cookie-free rather than merely `.ephemeral`.
/// `.ephemeral` only avoids writing cookies to *disk* — it still keeps an
/// in-memory `HTTPCookieStorage` and resends whatever it collects for the
/// lifetime of the `URLSession` object. Since this client outlives a single
/// request (one instance per `MusicShareKit.configure(_:)`), a merely
/// `.ephemeral` session accumulates the cookie from the first anonymous
/// sign-in and resends it on every subsequent one — better-auth then 400s
/// ("Anonymous users cannot sign in again anonymously") because it sees a
/// still-live session cookie, wedging auth until the process restarts
/// (#948).
///
/// Two independent guards, and both are needed:
/// - ``makeCookieFreeSession()`` disables cookie storage, acceptance, and
///   sending at the configuration level. This covers every request the
///   client grows in future, including one whose author forgets the flag
///   below.
/// - Each request sets `httpShouldHandleCookies = false`. This is the only
///   guard that survives an injected session — `init(session:)` accepts any
///   `URLSession`, and a caller passing a plain `.ephemeral` one gets a real
///   cookie jar that the configuration above never touched.
public struct DefaultAuthNetworkClient: AuthNetworkClient {
    private let session: URLSession

    public init(session: URLSession = DefaultAuthNetworkClient.makeCookieFreeSession()) {
        self.session = session
    }

    /// Builds the cookie-free session described on the type. `public`
    /// because it is `init(session:)`'s default argument, which is evaluated
    /// at each call site.
    public static func makeCookieFreeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        return URLSession(configuration: config)
    }

    public func signInAnonymously(
        baseURL: String, deviceFingerprint: String?
    ) async throws -> AnonymousSignInResult {
        guard let url = URL(string: "\(baseURL)/auth/sign-in/anonymous") else {
            throw SessionTokenProviderError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(baseURL, forHTTPHeaderField: "Origin")
        request.addValue(UserAgentHeader.value, forHTTPHeaderField: "User-Agent")
        if let deviceFingerprint {
            request.addValue(deviceFingerprint, forHTTPHeaderField: "X-Device-Fingerprint")
        }

        let response: (data: Data, response: URLResponse)
        do {
            response = try await session.data(for: request)
        } catch {
            throw AuthenticationError.networkError(error)
        }

        guard let httpResponse = response.response as? HTTPURLResponse else {
            throw AuthenticationError.invalidResponse
        }

        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            throw AuthenticationError.serverError(statusCode: httpResponse.statusCode)
        }

        do {
            let authResponse = try JSONDecoder.shared.decode(AuthResponse.self, from: response.data)
            return AnonymousSignInResult(
                sessionToken: authResponse.token,
                userId: authResponse.user.id
            )
        } catch {
            throw AuthenticationError.invalidResponse
        }
    }

    public func fetchJWT(
        baseURL: String, sessionToken: String, deviceFingerprint: String?
    ) async throws -> JWTExchangeResult {
        guard let url = URL(string: "\(baseURL)/auth/token") else {
            throw SessionTokenProviderError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(baseURL, forHTTPHeaderField: "Origin")
        request.addValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        request.addValue(UserAgentHeader.value, forHTTPHeaderField: "User-Agent")
        if let deviceFingerprint {
            request.addValue(deviceFingerprint, forHTTPHeaderField: "X-Device-Fingerprint")
        }

        let response: (data: Data, response: URLResponse)
        do {
            response = try await session.data(for: request)
        } catch {
            throw AuthenticationError.networkError(error)
        }

        guard let httpResponse = response.response as? HTTPURLResponse else {
            throw AuthenticationError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw AuthenticationError.serverError(statusCode: httpResponse.statusCode)
        }

        do {
            let tokenResponse = try JSONDecoder.shared.decode(JWTTokenResponse.self, from: response.data)
            // `value(forHTTPHeaderField:)` is a case-insensitive lookup, so
            // this captures the header however the server cases it. See
            // `JWTExchangeResult`'s doc comment for why the value is captured
            // but not acted on (#970).
            let capturedSessionToken = httpResponse.value(forHTTPHeaderField: "set-auth-token")
            return JWTExchangeResult(jwt: tokenResponse.token, capturedSessionToken: capturedSessionToken)
        } catch {
            throw AuthenticationError.invalidResponse
        }
    }
}

// MARK: - Response Models

/// Response from the anonymous sign-in endpoint.
private struct AuthResponse: Decodable {
    let token: String
    let user: AuthResponseUser

    struct AuthResponseUser: Decodable {
        let id: String
    }
}

/// Response from the JWT token exchange endpoint.
private struct JWTTokenResponse: Decodable {
    let token: String
}

// MARK: - Mock Implementation

/// Mock implementation of `AuthNetworkClient` for testing.
public final class MockAuthNetworkClient: AuthNetworkClient, @unchecked Sendable {

    /// The sign-in result to return, or `nil` to throw an error.
    public var mockSignInResult: AnonymousSignInResult?

    /// The error to throw from sign-in.
    public var mockError: Error?

    /// The JWT to return from token exchange, or `nil` to throw an error.
    public var mockJWT: String?

    /// The `set-auth-token` header value to surface alongside `mockJWT`, or
    /// `nil` for the (common) header-absent case (#970). Exists to drive the
    /// capture surface in tests — `AuthenticationService` ignores it, so
    /// setting this should never change persisted state.
    public var mockCapturedSessionToken: String?

    /// The error to throw from JWT exchange.
    public var mockJWTError: Error?

    /// The number of times sign-in was called.
    public private(set) var signInCallCount = 0

    /// The number of times JWT exchange was called.
    public private(set) var fetchJWTCallCount = 0

    /// Session tokens passed into `fetchJWT`, in call order. Useful for
    /// asserting that the refresh path uses the persisted session token.
    public private(set) var fetchJWTSessionTokens: [String] = []

    private let lock = NSLock()

    public init() {}

    /// Device fingerprints passed into `signInAnonymously`, in call order.
    public private(set) var signInDeviceFingerprints: [String?] = []

    /// Device fingerprints passed into `fetchJWT`, in call order.
    public private(set) var fetchJWTDeviceFingerprints: [String?] = []

    public func signInAnonymously(
        baseURL: String, deviceFingerprint: String?
    ) async throws -> AnonymousSignInResult {
        lock.withLock {
            signInCallCount += 1
            signInDeviceFingerprints.append(deviceFingerprint)
        }

        if let error = mockError {
            throw error
        }

        if let result = mockSignInResult {
            return result
        }

        throw AuthenticationError.networkError(URLError(.notConnectedToInternet))
    }

    public func fetchJWT(
        baseURL: String, sessionToken: String, deviceFingerprint: String?
    ) async throws -> JWTExchangeResult {
        lock.withLock {
            fetchJWTCallCount += 1
            fetchJWTSessionTokens.append(sessionToken)
            fetchJWTDeviceFingerprints.append(deviceFingerprint)
        }

        if let error = mockJWTError {
            throw error
        }

        if let jwt = mockJWT {
            return JWTExchangeResult(jwt: jwt, capturedSessionToken: mockCapturedSessionToken)
        }

        throw AuthenticationError.networkError(URLError(.notConnectedToInternet))
    }

    /// Resets all mock state.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        mockSignInResult = nil
        mockError = nil
        mockJWT = nil
        mockCapturedSessionToken = nil
        mockJWTError = nil
        signInCallCount = 0
        fetchJWTCallCount = 0
        fetchJWTSessionTokens.removeAll()
        signInDeviceFingerprints.removeAll()
        fetchJWTDeviceFingerprints.removeAll()
    }
}
