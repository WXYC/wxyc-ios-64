//
//  AuthNetworkClient.swift
//  MusicShareKit
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
    /// - Throws: `AuthenticationError` if the sign-in fails.
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
    /// - Returns: A JWT string.
    /// - Throws: `AuthenticationError` if the exchange fails.
    func fetchJWT(
        baseURL: String, sessionToken: String, deviceFingerprint: String?
    ) async throws -> String
}

// MARK: - Default Implementation

/// Default implementation of `AuthNetworkClient` using URLSession.
///
/// Uses an ephemeral session by default to avoid cookie contamination from
/// prior anonymous sessions (better-auth returns 400 if a valid session
/// cookie is already present).
public struct DefaultAuthNetworkClient: AuthNetworkClient {
    private let session: URLSession

    public init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    public func signInAnonymously(
        baseURL: String, deviceFingerprint: String?
    ) async throws -> AnonymousSignInResult {
        guard let url = URL(string: "\(baseURL)/auth/sign-in/anonymous") else {
            throw AuthenticationError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
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
    ) async throws -> String {
        guard let url = URL(string: "\(baseURL)/auth/token") else {
            throw AuthenticationError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
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
            return tokenResponse.token
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
    ) async throws -> String {
        lock.withLock {
            fetchJWTCallCount += 1
            fetchJWTSessionTokens.append(sessionToken)
            fetchJWTDeviceFingerprints.append(deviceFingerprint)
        }

        if let error = mockJWTError {
            throw error
        }

        if let jwt = mockJWT {
            return jwt
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
        mockJWTError = nil
        signInCallCount = 0
        fetchJWTCallCount = 0
        fetchJWTSessionTokens.removeAll()
        signInDeviceFingerprints.removeAll()
        fetchJWTDeviceFingerprints.removeAll()
    }
}
