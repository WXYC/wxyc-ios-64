//
//  AppConfigurationTests.swift
//  AppServices
//
//  Tests for AppConfiguration bootstrap config with defaults and network fetch.
//
//  Created by Jake Bromberg on 03/03/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import AppServices

@Suite("AppConfiguration Tests")
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
}

// MARK: - Test Helpers

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
