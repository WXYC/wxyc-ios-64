//
//  DefaultAuthNetworkClientTests.swift
//  MusicShareKit
//
//  Unit tests for DefaultAuthNetworkClient URL construction, headers, and response parsing.
//
//  Created by Jake Bromberg on 04/01/26.
//  Copyright © 2026 WXYC. All rights reserved.
//
//  #786: this file used to hand-roll a private `AuthRequestInterceptor` —
//  the same "configurable status code + body, capture the last request" job
//  `CoreTesting.QueuedStubURLProtocol` already does, with weaker guarantees
//  (`nonisolated(unsafe)` mutable state instead of a lock, safe only by
//  virtue of this suite's `.serialized` trait). It's gone; every test below
//  now calls `QueuedStubURLProtocol` directly. This suite is the bundle's
//  one adopting `@Suite` for that protocol; further adopters join it as
//  extensions (see `OEmbedClientTests.swift`), the same arrangement
//  Metadata's and Core's multi-adopter bundles use.
//

import Core
import CoreTesting
import Foundation
import Testing
@testable import MusicShareKit

// MARK: - URL and Header Tests

@Suite("DefaultAuthNetworkClient Tests", .serialized)
struct DefaultAuthNetworkClientTests {

    @Test("Sign-in URL uses /auth/sign-in/anonymous path")
    func signInURLPath() async throws {
        QueuedStubURLProtocol.setResponse(statusCode: 200, body: validBetterAuthResponse)

        let session = QueuedStubURLProtocol.makeSession()
        let client = DefaultAuthNetworkClient(session: session)

        _ = try await client.signInAnonymously(baseURL: "https://api.example.com", deviceFingerprint: nil)

        let capturedURL = try #require(QueuedStubURLProtocol.capturedRequest()?.url)
        #expect(capturedURL.path == "/auth/sign-in/anonymous")
        #expect(capturedURL.host() == "api.example.com")
    }

    @Test("Sign-in request includes Origin header matching baseURL")
    func signInOriginHeader() async throws {
        QueuedStubURLProtocol.setResponse(statusCode: 200, body: validBetterAuthResponse)

        let session = QueuedStubURLProtocol.makeSession()
        let client = DefaultAuthNetworkClient(session: session)

        _ = try await client.signInAnonymously(baseURL: "https://api.example.com", deviceFingerprint: nil)

        let origin = QueuedStubURLProtocol.capturedRequest()?.value(forHTTPHeaderField: "Origin")
        #expect(origin == "https://api.example.com")
    }

    @Test("Sign-in request uses POST method with JSON content type")
    func signInMethodAndContentType() async throws {
        QueuedStubURLProtocol.setResponse(statusCode: 200, body: validBetterAuthResponse)

        let session = QueuedStubURLProtocol.makeSession()
        let client = DefaultAuthNetworkClient(session: session)

        _ = try await client.signInAnonymously(baseURL: "https://api.example.com", deviceFingerprint: nil)

        let request = try #require(QueuedStubURLProtocol.capturedRequest())
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test("Sign-in sends X-Device-Fingerprint header when provided")
    func signInSendsDeviceFingerprintHeader() async throws {
        QueuedStubURLProtocol.setResponse(statusCode: 200, body: validBetterAuthResponse)

        let session = QueuedStubURLProtocol.makeSession()
        let client = DefaultAuthNetworkClient(session: session)

        _ = try await client.signInAnonymously(
            baseURL: "https://api.example.com",
            deviceFingerprint: "fingerprint-uuid-1234"
        )

        let header = QueuedStubURLProtocol.capturedRequest()?.value(forHTTPHeaderField: "X-Device-Fingerprint")
        #expect(header == "fingerprint-uuid-1234")
    }

    @Test("Sign-in omits X-Device-Fingerprint header when nil")
    func signInOmitsDeviceFingerprintHeader() async throws {
        QueuedStubURLProtocol.setResponse(statusCode: 200, body: validBetterAuthResponse)

        let session = QueuedStubURLProtocol.makeSession()
        let client = DefaultAuthNetworkClient(session: session)

        _ = try await client.signInAnonymously(
            baseURL: "https://api.example.com",
            deviceFingerprint: nil
        )

        let header = QueuedStubURLProtocol.capturedRequest()?.value(forHTTPHeaderField: "X-Device-Fingerprint")
        #expect(header == nil)
    }

    @Test("fetchJWT sends X-Device-Fingerprint header when provided")
    func fetchJWTSendsDeviceFingerprintHeader() async throws {
        QueuedStubURLProtocol.setResponse(statusCode: 200, body: validJWTTokenResponse)

        let session = QueuedStubURLProtocol.makeSession()
        let client = DefaultAuthNetworkClient(session: session)

        _ = try await client.fetchJWT(
            baseURL: "https://api.example.com",
            sessionToken: "sess-tok",
            deviceFingerprint: "fingerprint-uuid-5678"
        )

        let header = QueuedStubURLProtocol.capturedRequest()?.value(forHTTPHeaderField: "X-Device-Fingerprint")
        #expect(header == "fingerprint-uuid-5678")
    }

    @Test("fetchJWT omits X-Device-Fingerprint header when nil")
    func fetchJWTOmitsDeviceFingerprintHeader() async throws {
        QueuedStubURLProtocol.setResponse(statusCode: 200, body: validJWTTokenResponse)

        let session = QueuedStubURLProtocol.makeSession()
        let client = DefaultAuthNetworkClient(session: session)

        _ = try await client.fetchJWT(
            baseURL: "https://api.example.com",
            sessionToken: "sess-tok",
            deviceFingerprint: nil
        )

        let header = QueuedStubURLProtocol.capturedRequest()?.value(forHTTPHeaderField: "X-Device-Fingerprint")
        #expect(header == nil)
    }

    @Test("Sign-in sends User-Agent header")
    func signInSendsUserAgentHeader() async throws {
        QueuedStubURLProtocol.setResponse(statusCode: 200, body: validBetterAuthResponse)

        let session = QueuedStubURLProtocol.makeSession()
        let client = DefaultAuthNetworkClient(session: session)

        _ = try await client.signInAnonymously(
            baseURL: "https://api.example.com", deviceFingerprint: nil
        )

        let header = QueuedStubURLProtocol.capturedRequest()?.value(forHTTPHeaderField: "User-Agent")
        #expect(header == UserAgentHeader.value)
        // Format check: must match WXYC-iOS/<something>
        #expect(header?.hasPrefix("WXYC-iOS/") == true)
    }

    @Test("fetchJWT sends User-Agent header")
    func fetchJWTSendsUserAgentHeader() async throws {
        QueuedStubURLProtocol.setResponse(statusCode: 200, body: validJWTTokenResponse)

        let session = QueuedStubURLProtocol.makeSession()
        let client = DefaultAuthNetworkClient(session: session)

        _ = try await client.fetchJWT(
            baseURL: "https://api.example.com",
            sessionToken: "sess-tok",
            deviceFingerprint: nil
        )

        let header = QueuedStubURLProtocol.capturedRequest()?.value(forHTTPHeaderField: "User-Agent")
        #expect(header == UserAgentHeader.value)
    }

    // MARK: - Response Parsing Tests

    @Test("Parses better-auth anonymous response with nested user.id")
    func parsesBetterAuthResponse() async throws {
        QueuedStubURLProtocol.setResponse(statusCode: 200, body: validBetterAuthResponse)

        let session = QueuedStubURLProtocol.makeSession()
        let client = DefaultAuthNetworkClient(session: session)

        let authSession = try await client.signInAnonymously(baseURL: "https://api.example.com", deviceFingerprint: nil)

        #expect(authSession.sessionToken == "test-token-abc123")
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

        QueuedStubURLProtocol.setResponse(statusCode: 200, body: fullResponse)

        let session = QueuedStubURLProtocol.makeSession()
        let client = DefaultAuthNetworkClient(session: session)

        let authSession = try await client.signInAnonymously(baseURL: "https://api.example.com", deviceFingerprint: nil)

        #expect(authSession.sessionToken == "tok_123")
        #expect(authSession.userId == "usr_456")
    }

    // MARK: - Error Handling Tests

    @Test("Throws serverError for 403 status")
    func throwsServerErrorFor403() async throws {
        QueuedStubURLProtocol.setResponse(statusCode: 403, body: Data("""
        {"message": "Missing or null Origin", "code": "MISSING_OR_NULL_ORIGIN"}
        """.utf8))

        let session = QueuedStubURLProtocol.makeSession()
        let client = DefaultAuthNetworkClient(session: session)

        await #expect(throws: AuthenticationError.self) {
            _ = try await client.signInAnonymously(baseURL: "https://api.example.com", deviceFingerprint: nil)
        }
    }

    @Test("Throws invalidResponse for malformed JSON")
    func throwsInvalidResponseForMalformedJSON() async throws {
        QueuedStubURLProtocol.setResponse(statusCode: 200, body: Data("not json".utf8))

        let session = QueuedStubURLProtocol.makeSession()
        let client = DefaultAuthNetworkClient(session: session)

        await #expect(throws: AuthenticationError.self) {
            _ = try await client.signInAnonymously(baseURL: "https://api.example.com", deviceFingerprint: nil)
        }
    }

    @Test("Throws invalidResponse for old-format response with top-level user_id")
    func throwsForOldFormatResponse() async throws {
        let oldFormat = """
        {"token": "abc", "user_id": "123", "expires_at": "2026-04-02T00:00:00Z"}
        """.data(using: .utf8)!

        QueuedStubURLProtocol.setResponse(statusCode: 200, body: oldFormat)

        let session = QueuedStubURLProtocol.makeSession()
        let client = DefaultAuthNetworkClient(session: session)

        await #expect(throws: AuthenticationError.self) {
            _ = try await client.signInAnonymously(baseURL: "https://api.example.com", deviceFingerprint: nil)
        }
    }

    // MARK: - Cookie Isolation Tests (#948)
    //
    // A first attempt at these asserted `Cookie` absence on the SECOND
    // captured request, the way IOS-37 actually manifests over the wire.
    // That assertion is vacuous: `QueuedStubURLProtocol`'s synthetic
    // response never round-trips through `URLSession`'s cookie-storage
    // machinery at all — a `Set-Cookie` response header is never stored,
    // and outgoing requests never gain a `Cookie` header, regardless of
    // whether the session is cookie-free. Confirmed empirically: the
    // Cookie-header assertion passed against completely unfixed
    // (`.ephemeral`, no cookie-disabling) production code. Reassigned to
    // two layers that ARE reachable from a unit test: the session's own
    // `URLSessionConfiguration` (no network round trip needed at all), and
    // the per-request `httpShouldHandleCookies` flag (a plain `URLRequest`
    // property `QueuedStubURLProtocol` captures faithfully, independent of
    // whatever cookie machinery does or doesn't run underneath it).

    @Test("makeSession() produces a session configuration with no cookie storage, set-cookie acceptance, or send policy")
    func makeSessionConfigurationIsCookieFree() {
        let session = DefaultAuthNetworkClient.makeSession()

        #expect(session.configuration.httpCookieStorage == nil)
        #expect(session.configuration.httpShouldSetCookies == false)
        #expect(session.configuration.httpCookieAcceptPolicy == .never)
    }

    @Test("Sign-in and fetchJWT requests both opt out of cookie handling")
    func requestsOptOutOfCookieHandling() async throws {
        QueuedStubURLProtocol.setResponses([
            (200, validBetterAuthResponse),
            (200, validJWTTokenResponse),
        ])

        let session = QueuedStubURLProtocol.makeSession()
        let client = DefaultAuthNetworkClient(session: session)

        _ = try await client.signInAnonymously(baseURL: "https://api.example.com", deviceFingerprint: nil)
        _ = try await client.fetchJWT(baseURL: "https://api.example.com", sessionToken: "sess-tok", deviceFingerprint: nil)

        let requests = QueuedStubURLProtocol.capturedRequests()
        #expect(requests.count == 2)
        for request in requests {
            #expect(request.httpShouldHandleCookies == false)
        }
    }

    @Test("Sign-in throws the canonical notConfigured error for a malformed baseURL")
    func signInThrowsNotConfiguredForMalformedBaseURL() async throws {
        let client = DefaultAuthNetworkClient()

        // "http://[" (unclosed IPv6 literal) is one of the few shapes even
        // the lenient iOS 17+ URL parser rejects, so the guard fires before
        // any network request is attempted.
        await #expect(throws: SessionTokenProviderError.notConfigured) {
            _ = try await client.signInAnonymously(baseURL: "http://[", deviceFingerprint: nil)
        }
    }

    // MARK: - fetchJWT Tests

    @Test("fetchJWT URL uses GET /auth/token path")
    func fetchJWTURLPath() async throws {
        QueuedStubURLProtocol.setResponse(statusCode: 200, body: validJWTTokenResponse)

        let session = QueuedStubURLProtocol.makeSession()
        let client = DefaultAuthNetworkClient(session: session)

        _ = try await client.fetchJWT(baseURL: "https://api.example.com", sessionToken: "session-tok", deviceFingerprint: nil)

        let capturedURL = try #require(QueuedStubURLProtocol.capturedRequest()?.url)
        #expect(capturedURL.path == "/auth/token")
        #expect(capturedURL.host() == "api.example.com")

        let request = try #require(QueuedStubURLProtocol.capturedRequest())
        #expect(request.httpMethod == "GET")
    }

    @Test("fetchJWT includes Authorization: Bearer header with session token")
    func fetchJWTAuthorizationHeader() async throws {
        QueuedStubURLProtocol.setResponse(statusCode: 200, body: validJWTTokenResponse)

        let session = QueuedStubURLProtocol.makeSession()
        let client = DefaultAuthNetworkClient(session: session)

        _ = try await client.fetchJWT(baseURL: "https://api.example.com", sessionToken: "my-session-token", deviceFingerprint: nil)

        let auth = QueuedStubURLProtocol.capturedRequest()?.value(forHTTPHeaderField: "Authorization")
        #expect(auth == "Bearer my-session-token")
    }

    @Test("fetchJWT includes Origin header matching baseURL")
    func fetchJWTOriginHeader() async throws {
        QueuedStubURLProtocol.setResponse(statusCode: 200, body: validJWTTokenResponse)

        let session = QueuedStubURLProtocol.makeSession()
        let client = DefaultAuthNetworkClient(session: session)

        _ = try await client.fetchJWT(baseURL: "https://api.example.com", sessionToken: "tok", deviceFingerprint: nil)

        let origin = QueuedStubURLProtocol.capturedRequest()?.value(forHTTPHeaderField: "Origin")
        #expect(origin == "https://api.example.com")
    }

    @Test("fetchJWT returns token string from response")
    func fetchJWTReturnsToken() async throws {
        QueuedStubURLProtocol.setResponse(statusCode: 200, body: validJWTTokenResponse)

        let session = QueuedStubURLProtocol.makeSession()
        let client = DefaultAuthNetworkClient(session: session)

        let jwt = try await client.fetchJWT(baseURL: "https://api.example.com", sessionToken: "tok", deviceFingerprint: nil)

        #expect(jwt == "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyMTIzIiwiZXhwIjoxNzM1Njg5NjAwfQ.fakesig")
    }

    @Test("fetchJWT throws serverError for non-200 status")
    func fetchJWTThrowsServerError() async throws {
        QueuedStubURLProtocol.setResponse(statusCode: 401, body: Data("""
        {"error": "Unauthorized"}
        """.utf8))

        let session = QueuedStubURLProtocol.makeSession()
        let client = DefaultAuthNetworkClient(session: session)

        await #expect(throws: AuthenticationError.self) {
            _ = try await client.fetchJWT(baseURL: "https://api.example.com", sessionToken: "bad-tok", deviceFingerprint: nil)
        }
    }

    @Test("fetchJWT throws invalidResponse for missing token field")
    func fetchJWTThrowsInvalidResponseForMissingToken() async throws {
        QueuedStubURLProtocol.setResponse(statusCode: 200, body: Data("""
        {"error": "nope"}
        """.utf8))

        let session = QueuedStubURLProtocol.makeSession()
        let client = DefaultAuthNetworkClient(session: session)

        await #expect(throws: AuthenticationError.self) {
            _ = try await client.fetchJWT(baseURL: "https://api.example.com", sessionToken: "tok", deviceFingerprint: nil)
        }
    }

    @Test("fetchJWT throws the canonical notConfigured error for a malformed baseURL")
    func fetchJWTThrowsNotConfiguredForMalformedBaseURL() async throws {
        let client = DefaultAuthNetworkClient()

        // See signInThrowsNotConfiguredForMalformedBaseURL for the choice
        // of "http://[".
        await #expect(throws: SessionTokenProviderError.notConfigured) {
            _ = try await client.fetchJWT(baseURL: "http://[", sessionToken: "tok", deviceFingerprint: nil)
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

private let validJWTTokenResponse = """
{
    "token": "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyMTIzIiwiZXhwIjoxNzM1Njg5NjAwfQ.fakesig"
}
""".data(using: .utf8)!
