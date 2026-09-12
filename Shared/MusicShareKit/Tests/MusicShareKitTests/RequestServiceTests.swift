//
//  RequestServiceTests.swift
//  MusicShareKit
//
//  Tests for RequestService song request behavior.
//
//  Created by Jake Bromberg on 11/25/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import AnalyticsTesting
import Foundation
import Testing
@testable import MusicShareKit

@Suite("RequestService Tests")
struct RequestServiceTests {

    init() {
        // Configure MusicShareKit before running tests.
        //
        // Explicitly pass `InMemoryDeviceFingerprintStorage` — the default is
        // `KeychainDeviceFingerprintStorage` which round-trips through the
        // system Keychain. Under MusicShareKitTests' parallelizable execution,
        // many concurrent test inits cause Keychain-daemon contention that
        // can hang the test process on CI simulators (the local iPhone 17 sim
        // returns errSecMissingEntitlement instantly; the iPhone 16 Pro CI sim
        // does not).
        MusicShareKit.reconfigure(MusicShareKitConfiguration(
            requestOMaticURL: "https://example.com/request",
            analyticsService: MockStructuredAnalytics(),
            deviceFingerprintStorage: InMemoryDeviceFingerprintStorage()
        ))
    }
    
    @Test("Empty message throws error")
    func emptyMessageThrowsError() async {
        do {
            try await RequestService.shared.sendRequest(message: "")
            #expect(Bool(false), "Expected error to be thrown")
        } catch let error as RequestServiceError {
            #expect(error == .emptyMessage)
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }
    
    @Test("Configuration is accessible after configure() is called")
    func configurationIsAccessible() {
        let config = MusicShareKit.configuration
        #expect(config.requestOMaticURL == "https://example.com/request")
    }
    
    @Test("sendRequest hits the configured URL")
    func sendRequestUsesConfiguredURL() async throws {
        let session = MockRequestSession()
        let service = RequestService(session: session)

        try await service.sendRequest(message: "la paradoja by Juana Molina")

        let recordedURL = try #require(await session.lastRequest?.url)
        #expect(recordedURL.absoluteString == "https://example.com/request")
        #expect(await session.invocationCount == 1)
    }

    @Test("A 401 whose token was already superseded retries with the refreshed JWT without a redundant sign-in")
    func retryAfter401ReusesAlreadyRefreshedSession() async throws {
        let storage = InMemoryTokenStorage()
        let initialSession = AuthSession(
            sessionToken: "request-session-token",
            jwt: makeRequestTestJWT(sub: "initial"),
            userId: "request-user",
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(3600)
        )
        try storage.save(initialSession)

        let networkClient = MockAuthNetworkClient()
        networkClient.mockJWT = makeRequestTestJWT(sub: "refreshed")
        let authService = AuthenticationService(
            storage: storage,
            networkClient: networkClient,
            baseURL: "https://auth.example.com",
            analytics: MockStructuredAnalytics(),
            fingerprintMode: .existing,
            prematureAccessCount: 0
        )

        // Warm the cache with the (about-to-be-rejected) stored JWT.
        let staleToken = try await authService.ensureAuthenticated()
        #expect(staleToken == initialSession.jwt)

        let session = SupersededTokenSession(authService: authService)
        let service = RequestService(session: session, authService: authService)

        try await service.sendRequest(message: "la paradoja by Juana Molina")

        // First attempt carried the stale token; the retry must carry the
        // token the concurrent recovery minted.
        let headers = await session.authorizationHeaders
        let refreshedToken = try #require(await session.refreshedToken)
        #expect(headers.count == 2)
        #expect(headers[0] == "Bearer \(staleToken)")
        #expect(headers[1] == "Bearer \(refreshedToken)")

        // The only network auth call is the concurrent recovery's mint. The
        // request-line 401 handler must reuse the refreshed session — not
        // wipe it and force another refresh/sign-in of its own.
        #expect(networkClient.fetchJWTCallCount == 1)
        #expect(networkClient.signInCallCount == 0)
    }

    // Pins the 2026-08-27 decision (iOS#1011): the request line hard-fails on
    // an auth failure rather than falling back to an unauthenticated POST.
    // A future well-meaning "fall back so the listener isn't blocked" change
    // would make this test fail by having the network session observe a call.
    @Test("No request is sent when authentication cannot be established")
    func noRequestSentWhenAuthenticationFails() async {
        let networkClient = MockAuthNetworkClient()
        networkClient.mockError = URLError(.notConnectedToInternet)
        let authService = AuthenticationService(
            storage: InMemoryTokenStorage(),
            networkClient: networkClient,
            baseURL: "https://auth.example.com",
            analytics: MockStructuredAnalytics(),
            fingerprintMode: .existing,
            prematureAccessCount: 0
        )

        let session = NeverCalledSession()
        let service = RequestService(session: session, authService: authService)

        await #expect(throws: RequestServiceError.self) {
            try await service.sendRequest(message: "la paradoja by Juana Molina")
        }
        #expect(await session.invocationCount == 0)
    }
}

/// `RequestSession` that 401s the first request — but only after simulating a
/// CONCURRENT caller recovering from the same rejected token (so the auth
/// service's cache has already moved past it by the time the request-line 401
/// handler runs) — and 200s the retry. Records the `Authorization` header of
/// every request so the test can assert which token each attempt carried.
private actor SupersededTokenSession: RequestSession {
    private let authService: AuthenticationService
    private(set) var authorizationHeaders: [String?] = []
    private(set) var refreshedToken: String?

    init(authService: AuthenticationService) {
        self.authService = authService
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        authorizationHeaders.append(request.value(forHTTPHeaderField: "Authorization"))
        let statusCode: Int
        if authorizationHeaders.count == 1 {
            // Another caller (e.g. an On Tour fetch) recovers from the same
            // rejected token while this request's 401 is still in flight.
            refreshedToken = try await authService.reauthenticate(reason: .unauthorized)
            statusCode = 401
        } else {
            statusCode = 200
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(), response)
    }
}

/// Creates a structurally valid JWT (decodable payload, fake signature) with
/// a future `exp`, distinguishable by `sub` so tests can mint distinct tokens.
private func makeRequestTestJWT(sub: String) -> String {
    func base64urlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    let header = base64urlEncode(Data("{\"alg\":\"HS256\"}".utf8))
    let exp = Int(Date().addingTimeInterval(3600).timeIntervalSince1970)
    let payload = base64urlEncode(Data("{\"sub\":\"\(sub)\",\"exp\":\(exp)}".utf8))
    return "\(header).\(payload).fakesignature"
}

/// `RequestSession` that fails the test if it is ever asked to send a
/// request — the double for asserting a request never leaves the device.
private actor NeverCalledSession: RequestSession {
    private(set) var invocationCount = 0

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        invocationCount += 1
        throw URLError(.unknown)
    }
}

/// In-memory `RequestSession` that records the last request and returns a 200 response.
private actor MockRequestSession: RequestSession {
    var lastRequest: URLRequest?
    var invocationCount = 0

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        invocationCount += 1
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(), response)
    }
}

extension RequestServiceError: Equatable {
    public static func == (lhs: RequestServiceError, rhs: RequestServiceError) -> Bool {
        switch (lhs, rhs) {
        case (.emptyMessage, .emptyMessage):
            return true
        case (.encodingFailed, .encodingFailed):
            return true
        case (.invalidResponse, .invalidResponse):
            return true
        case (.serverError(let lhsCode), .serverError(let rhsCode)):
            return lhsCode == rhsCode
        case (.networkError, .networkError):
            return true // Can't compare underlying errors easily
        default:
            return false
        }
    }
}
