//
//  AppConfigurationTests.swift
//  AppServices
//
//  Tests for AppConfiguration bootstrap config with defaults and network fetch.
//
//  Created by Jake Bromberg on 03/03/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Core
import Foundation
import Testing
@testable import AppServices

// `.serialized` because the network-fetch tests share `MockURLProtocol.handler`
// (URLProtocol registration is class-level, so the handler has to be static).
// Without serialization, two tests set the handler at the same time and one
// of them ends up routing its URLSession call through the other's handler.
@Suite("AppConfiguration Tests", .serialized)
struct AppConfigurationTests {

    // MARK: - Static Defaults

    @Test("defaults provides expected PostHog API key")
    func defaultsProvidesPostHogApiKey() {
        #expect(!AppConfiguration.defaults.posthogApiKey.isEmpty)
    }

    @Test("defaults provides expected PostHog host")
    func defaultsProvidesPostHogHost() {
        #expect(AppConfiguration.defaults.posthogHost == "https://us.i.posthog.com")
    }

    @Test("defaults provides expected request-o-matic URL")
    func defaultsProvidesRequestOMaticUrl() {
        #expect(AppConfiguration.defaults.requestOMaticUrl.hasPrefix("https://"))
    }

    @Test("defaults provides expected API base URL")
    func defaultsProvidesApiBaseUrl() {
        #expect(AppConfiguration.defaults.apiBaseUrl == "https://api.wxyc.org")
    }

    @Test("apiBaseUrl static constant matches defaults")
    func apiBaseUrlConstantMatchesDefaults() {
        #expect(AppConfiguration.apiBaseUrl == AppConfiguration.defaults.apiBaseUrl)
    }

    @Test("keychainAccessGroup matches the entitlement format")
    func keychainAccessGroupMatchesEntitlement() {
        // Must exactly match the resolved value of
        // $(AppIdentifierPrefix)group.wxyc.iphone in every target's
        // keychain-access-groups entitlement. Mismatch silently breaks
        // session sharing between the main app and Share Extension (issue #336).
        #expect(AppConfiguration.keychainAccessGroup == "92V374HC38.group.wxyc.iphone")
    }

    // MARK: - Network Fetch

    @Test("config returns fetched values when network succeeds")
    func configReturnsFetchedValues() async {
        let expected = AppConfig(
            posthogApiKey: "phc_test_key",
            posthogHost: "https://test.posthog.com",
            requestOMaticUrl: "https://test.example.com/request",
            apiBaseUrl: "https://test.api.wxyc.org"
        )

        let session = MockURLProtocol.session { request in
            let data = try! JSONEncoder().encode(expected)
            return (data, HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!)
        }

        let configuration = AppConfiguration(session: session)
        let config = await configuration.config()

        #expect(config == expected)
    }

    @Test("config returns defaults when network fails")
    func configReturnsDefaultsOnNetworkFailure() async {
        let session = MockURLProtocol.session { _ in
            throw URLError(.notConnectedToInternet)
        }

        let configuration = AppConfiguration(session: session)
        let config = await configuration.config()

        #expect(config == AppConfiguration.defaults)
    }

    @Test("config caches the fetched result")
    func configCachesFetchedResult() async {
        var callCount = 0
        let expected = AppConfig(
            posthogApiKey: "phc_cached",
            posthogHost: "https://cached.posthog.com",
            requestOMaticUrl: "https://cached.example.com/request",
            apiBaseUrl: "https://cached.api.wxyc.org"
        )

        let session = MockURLProtocol.session { request in
            callCount += 1
            let data = try! JSONEncoder().encode(expected)
            return (data, HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!)
        }

        let configuration = AppConfiguration(session: session)
        _ = await configuration.config()
        _ = await configuration.config()

        #expect(callCount == 1)
    }

    @Test("config returns defaults on non-200 status code")
    func configReturnsDefaultsOnBadStatusCode() async {
        let session = MockURLProtocol.session { request in
            let data = Data()
            return (data, HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!)
        }

        let configuration = AppConfiguration(session: session)
        let config = await configuration.config()

        #expect(config == AppConfiguration.defaults)
    }

    @Test("config returns defaults on malformed JSON")
    func configReturnsDefaultsOnMalformedJson() async {
        let session = MockURLProtocol.session { request in
            let data = "not json".data(using: .utf8)!
            return (data, HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!)
        }

        let configuration = AppConfiguration(session: session)
        let config = await configuration.config()

        #expect(config == AppConfiguration.defaults)
    }

    // MARK: - Secrets Fetch

    @Test("fetchSecrets recovers from a stale-token 401 by reauthenticating and retrying once")
    func fetchSecretsRetriesOn401() async throws {
        // The exact #715 cold-launch condition: the cached JWT was rejected
        // server-side. fetchSecrets must go through the shared authedData
        // seam — reauthenticate, retry once with the fresh token — instead
        // of collapsing the 401 to nil (secrets silently missing for the
        // whole session).
        nonisolated(unsafe) var capturedAuthorizationHeaders: [String?] = []
        let session = MockURLProtocol.session { request in
            capturedAuthorizationHeaders.append(request.value(forHTTPHeaderField: "Authorization"))
            if capturedAuthorizationHeaders.count == 1 {
                return (Data(), HTTPURLResponse(
                    url: request.url!,
                    statusCode: 401,
                    httpVersion: nil,
                    headerFields: nil
                )!)
            }
            let body = #"{"discogsApiKey": "test-key", "discogsApiSecret": "test-secret"}"#
            return (Data(body.utf8), HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!)
        }

        let tokenProvider = RecordingTokenProvider(
            initialToken: "stale-token",
            refreshedToken: "fresh-token"
        )
        let configuration = AppConfiguration(session: session)
        let secrets = await configuration.fetchSecrets(tokenProvider: tokenProvider)

        #expect(secrets?.discogsApiKey == "test-key")
        #expect(secrets?.discogsApiSecret == "test-secret")
        #expect(await tokenProvider.reauthenticateCallCount == 1)
        #expect(capturedAuthorizationHeaders.count == 2)
        #expect(capturedAuthorizationHeaders[0] == "Bearer stale-token")
        #expect(capturedAuthorizationHeaders[1] == "Bearer fresh-token")
    }

    @Test("fetchSecrets returns nil on a persistent non-2xx response")
    func fetchSecretsReturnsNilOnServerError() async {
        let session = MockURLProtocol.session { request in
            (Data(), HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!)
        }

        let tokenProvider = RecordingTokenProvider(
            initialToken: "stale-token",
            refreshedToken: "fresh-token"
        )
        let configuration = AppConfiguration(session: session)
        let secrets = await configuration.fetchSecrets(tokenProvider: tokenProvider)

        #expect(secrets == nil)
    }
}

// MARK: - Test Helpers

/// A `SessionTokenProvider` returning a distinct `initialToken` from `token()`
/// and `refreshedToken` from `reauthenticate(previousToken:)`, recording the
/// reauthentication count so 401-retry tests can assert "exactly once".
private actor RecordingTokenProvider: SessionTokenProvider {
    private(set) var reauthenticateCallCount = 0
    private let initialToken: String
    private let refreshedToken: String

    init(initialToken: String, refreshedToken: String) {
        self.initialToken = initialToken
        self.refreshedToken = refreshedToken
    }

    func token() async throws -> String { initialToken }

    func reauthenticate(previousToken: String) async throws -> String {
        reauthenticateCallCount += 1
        return refreshedToken
    }
}

/// A URLProtocol subclass that intercepts requests and returns mock responses.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Data, URLResponse))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        do {
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    /// Creates a URLSession configured to use this mock protocol with the given handler.
    static func session(handler: @escaping (URLRequest) throws -> (Data, URLResponse)) -> URLSession {
        self.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}
