//
//  DefaultAuthNetworkClientTests.swift
//  MusicShareKit
//
//  Unit tests for DefaultAuthNetworkClient URL construction, headers, and response parsing.
//
//  Created by Jake Bromberg on 04/01/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import MusicShareKit

// MARK: - URL and Header Tests

@Suite("DefaultAuthNetworkClient Tests", .serialized)
struct DefaultAuthNetworkClientTests {

    @Test("Sign-in URL uses /auth/sign-in/anonymous path")
    func signInURLPath() async throws {
        let interceptor = AuthRequestInterceptor()
        interceptor.responseBody = validBetterAuthResponse
        interceptor.responseStatusCode = 200

        let session = makeSession(interceptor: interceptor)
        let client = DefaultAuthNetworkClient(session: session)

        _ = try await client.signInAnonymously(baseURL: "https://api.example.com")

        let capturedURL = try #require(interceptor.lastRequest?.url)
        #expect(capturedURL.path == "/auth/sign-in/anonymous")
        #expect(capturedURL.host() == "api.example.com")
    }

    @Test("Sign-in request includes Origin header matching baseURL")
    func signInOriginHeader() async throws {
        let interceptor = AuthRequestInterceptor()
        interceptor.responseBody = validBetterAuthResponse
        interceptor.responseStatusCode = 200

        let session = makeSession(interceptor: interceptor)
        let client = DefaultAuthNetworkClient(session: session)

        _ = try await client.signInAnonymously(baseURL: "https://api.example.com")

        let origin = interceptor.lastRequest?.value(forHTTPHeaderField: "Origin")
        #expect(origin == "https://api.example.com")
    }

    @Test("Sign-in request uses POST method with JSON content type")
    func signInMethodAndContentType() async throws {
        let interceptor = AuthRequestInterceptor()
        interceptor.responseBody = validBetterAuthResponse
        interceptor.responseStatusCode = 200

        let session = makeSession(interceptor: interceptor)
        let client = DefaultAuthNetworkClient(session: session)

        _ = try await client.signInAnonymously(baseURL: "https://api.example.com")

        let request = try #require(interceptor.lastRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    // MARK: - Response Parsing Tests

    @Test("Parses better-auth anonymous response with nested user.id")
    func parsesBetterAuthResponse() async throws {
        let interceptor = AuthRequestInterceptor()
        interceptor.responseBody = validBetterAuthResponse
        interceptor.responseStatusCode = 200

        let session = makeSession(interceptor: interceptor)
        let client = DefaultAuthNetworkClient(session: session)

        let authSession = try await client.signInAnonymously(baseURL: "https://api.example.com")

        #expect(authSession.token == "test-token-abc123")
        #expect(authSession.userId == "user-xyz-789")
    }

    @Test("Parses response with additional user fields without failing")
    func parsesResponseWithExtraFields() async throws {
        let fullResponse = """
        {
            "token": "tok_123",
            "user": {
                "id": "usr_456",
                "name": "Anonymous",
                "email": "temp@anonymous.wxyc.org",
                "emailVerified": false,
                "image": null,
                "createdAt": "2026-04-01T21:00:00.000Z",
                "role": "user",
                "isAnonymous": true,
                "capabilities": []
            }
        }
        """.data(using: .utf8)!

        let interceptor = AuthRequestInterceptor()
        interceptor.responseBody = fullResponse
        interceptor.responseStatusCode = 200

        let session = makeSession(interceptor: interceptor)
        let client = DefaultAuthNetworkClient(session: session)

        let authSession = try await client.signInAnonymously(baseURL: "https://api.example.com")

        #expect(authSession.token == "tok_123")
        #expect(authSession.userId == "usr_456")
    }

    // MARK: - Error Handling Tests

    @Test("Throws serverError for 403 status")
    func throwsServerErrorFor403() async throws {
        let interceptor = AuthRequestInterceptor()
        interceptor.responseBody = """
        {"message": "Missing or null Origin", "code": "MISSING_OR_NULL_ORIGIN"}
        """.data(using: .utf8)!
        interceptor.responseStatusCode = 403

        let session = makeSession(interceptor: interceptor)
        let client = DefaultAuthNetworkClient(session: session)

        await #expect(throws: AuthenticationError.self) {
            _ = try await client.signInAnonymously(baseURL: "https://api.example.com")
        }
    }

    @Test("Throws invalidResponse for malformed JSON")
    func throwsInvalidResponseForMalformedJSON() async throws {
        let interceptor = AuthRequestInterceptor()
        interceptor.responseBody = "not json".data(using: .utf8)!
        interceptor.responseStatusCode = 200

        let session = makeSession(interceptor: interceptor)
        let client = DefaultAuthNetworkClient(session: session)

        await #expect(throws: AuthenticationError.self) {
            _ = try await client.signInAnonymously(baseURL: "https://api.example.com")
        }
    }

    @Test("Throws invalidResponse for old-format response with top-level user_id")
    func throwsForOldFormatResponse() async throws {
        let oldFormat = """
        {"token": "abc", "user_id": "123", "expires_at": "2026-04-02T00:00:00Z"}
        """.data(using: .utf8)!

        let interceptor = AuthRequestInterceptor()
        interceptor.responseBody = oldFormat
        interceptor.responseStatusCode = 200

        let session = makeSession(interceptor: interceptor)
        let client = DefaultAuthNetworkClient(session: session)

        await #expect(throws: AuthenticationError.self) {
            _ = try await client.signInAnonymously(baseURL: "https://api.example.com")
        }
    }
}

// MARK: - Test Helpers

private let validBetterAuthResponse = """
{
    "token": "test-token-abc123",
    "user": {
        "id": "user-xyz-789",
        "name": "Anonymous",
        "email": "temp@anonymous.wxyc.org"
    }
}
""".data(using: .utf8)!

/// URLProtocol subclass that intercepts requests and returns configured responses.
private final class AuthRequestInterceptor: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var current: AuthRequestInterceptor?

    nonisolated(unsafe) var responseBody: Data = Data()
    nonisolated(unsafe) var responseStatusCode: Int = 200
    nonisolated(unsafe) var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.current?.lastRequest = request

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.current?.responseStatusCode ?? 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.current?.responseBody ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func makeSession(interceptor: AuthRequestInterceptor) -> URLSession {
    AuthRequestInterceptor.current = interceptor
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [AuthRequestInterceptor.self]
    return URLSession(configuration: config)
}
