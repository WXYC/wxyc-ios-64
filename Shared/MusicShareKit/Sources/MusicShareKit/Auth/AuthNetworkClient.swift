//
//  AuthNetworkClient.swift
//  MusicShareKit
//
//  Protocol and default implementation for authentication network requests.
//
//  Created by Jake Bromberg on 01/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Protocol for making authentication network requests.
///
/// Allows mocking the network layer in tests.
public protocol AuthNetworkClient: Sendable {

    /// Signs in anonymously and returns a new authentication session.
    ///
    /// - Parameter baseURL: The base URL for the authentication API.
    /// - Returns: A new authentication session.
    /// - Throws: `AuthenticationError` if the sign-in fails.
    func signInAnonymously(baseURL: String) async throws -> AuthSession
}

// MARK: - Default Implementation

/// Default implementation of `AuthNetworkClient` using URLSession.
public struct DefaultAuthNetworkClient: AuthNetworkClient {

    public init() {}

    public func signInAnonymously(baseURL: String) async throws -> AuthSession {
        guard let url = URL(string: "\(baseURL)/auth/anonymous") else {
            throw AuthenticationError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let response: (data: Data, response: URLResponse)
        do {
            response = try await URLSession.shared.data(for: request)
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
            let authResponse = try JSONDecoder().decode(AuthResponse.self, from: response.data)
            return AuthSession(
                token: authResponse.token,
                userId: authResponse.userId,
                createdAt: Date(),
                expiresAt: authResponse.expiresAt
            )
        } catch {
            throw AuthenticationError.invalidResponse
        }
    }
}

// MARK: - Response Model

/// Response from the anonymous sign-in endpoint.
private struct AuthResponse: Decodable {
    let token: String
    let userId: String
    let expiresAt: Date?

    private enum CodingKeys: String, CodingKey {
        case token
        case userId = "user_id"
        case expiresAt = "expires_at"
    }
}

// MARK: - Mock Implementation

/// Mock implementation of `AuthNetworkClient` for testing.
public final class MockAuthNetworkClient: AuthNetworkClient, @unchecked Sendable {

    /// The session to return from sign-in, or `nil` to throw an error.
    public var mockSession: AuthSession?

    /// The error to throw from sign-in.
    public var mockError: Error?

    /// The number of times sign-in was called.
    public private(set) var signInCallCount = 0

    private let lock = NSLock()

    public init() {}

    public func signInAnonymously(baseURL: String) async throws -> AuthSession {
        lock.withLock { signInCallCount += 1 }

        if let error = mockError {
            throw error
        }

        if let session = mockSession {
            return session
        }

        throw AuthenticationError.networkError(URLError(.notConnectedToInternet))
    }

    /// Resets all mock state.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        mockSession = nil
        mockError = nil
        signInCallCount = 0
    }
}
