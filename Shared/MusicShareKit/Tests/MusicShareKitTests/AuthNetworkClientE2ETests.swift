//
//  AuthNetworkClientE2ETests.swift
//  MusicShareKit
//
//  E2E tests that hit the real backend to verify anonymous auth and token usage.
//  These tests require network access to api.wxyc.org.
//
//  Created by Jake Bromberg on 04/01/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import MusicShareKit

@Suite(
    "AuthNetworkClient E2E Tests",
    .tags(.e2e),
    .disabled(if: ProcessInfo.processInfo.environment["RUN_E2E"] != "1")
)
struct AuthNetworkClientE2ETests {

    let baseURL = "https://api.wxyc.org"

    /// Creates a client that uses an ephemeral session to avoid cookie contamination between tests.
    func makeClient() -> DefaultAuthNetworkClient {
        DefaultAuthNetworkClient(session: URLSession(configuration: .ephemeral))
    }

    @Test("Anonymous sign-in returns a valid session")
    func anonymousSignInReturnsValidSession() async throws {
        let session = try await makeClient().signInAnonymously(baseURL: baseURL)

        #expect(!session.token.isEmpty)
        #expect(!session.userId.isEmpty)
    }

    @Test("Token from anonymous sign-in authenticates against /config/secrets")
    func tokenAuthenticatesAgainstSecrets() async throws {
        let session = try await makeClient().signInAnonymously(baseURL: baseURL)

        var request = URLRequest(url: URL(string: "\(baseURL)/config/secrets")!)
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try #require(response as? HTTPURLResponse)

        #expect(httpResponse.statusCode == 200)

        let secrets = try JSONDecoder().decode(SecretsResponse.self, from: data)
        #expect(!secrets.discogsApiKey.isEmpty)
        #expect(!secrets.discogsApiSecret.isEmpty)
    }

    @Test("Token from anonymous sign-in authenticates against metadata proxy")
    func tokenAuthenticatesAgainstMetadataProxy() async throws {
        let session = try await makeClient().signInAnonymously(baseURL: baseURL)

        var components = URLComponents(string: "\(baseURL)/proxy/metadata/album")!
        components.queryItems = [
            URLQueryItem(name: "artistName", value: "Autechre"),
            URLQueryItem(name: "releaseTitle", value: "Confield"),
            URLQueryItem(name: "trackTitle", value: "VI Scose Poise"),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try #require(response as? HTTPURLResponse)

        #expect(httpResponse.statusCode == 200)
    }

    // MARK: - JWT Exchange Tests

    @Test("JWT exchange returns a valid JWT with three segments")
    func jwtExchangeReturnsValidJWT() async throws {
        let client = makeClient()
        let session = try await client.signInAnonymously(baseURL: baseURL)

        let jwt = try await client.fetchJWT(baseURL: baseURL, sessionToken: session.token)

        let segments = jwt.split(separator: ".")
        #expect(segments.count == 3)

        // Verify the JWT payload can be decoded with an exp claim
        let payload = try JWTPayloadDecoder.decode(jwt)
        #expect(payload.expiresAt > Date())
    }

    @Test("JWT from exchange authenticates against /config/secrets")
    func jwtAuthenticatesAgainstSecrets() async throws {
        let client = makeClient()
        let session = try await client.signInAnonymously(baseURL: baseURL)
        let jwt = try await client.fetchJWT(baseURL: baseURL, sessionToken: session.token)

        var request = URLRequest(url: URL(string: "\(baseURL)/config/secrets")!)
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try #require(response as? HTTPURLResponse)

        #expect(httpResponse.statusCode == 200)

        let secrets = try JSONDecoder().decode(SecretsResponse.self, from: data)
        #expect(!secrets.discogsApiKey.isEmpty)
    }
}

/// Minimal decode type for /config/secrets response
private struct SecretsResponse: Codable {
    let discogsApiKey: String
    let discogsApiSecret: String
}

extension Tag {
    @Tag static var e2e: Self
}
