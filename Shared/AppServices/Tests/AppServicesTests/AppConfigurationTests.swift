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
import CoreTesting
import Foundation
import Testing
@testable import AppServices

// `.serialized` because the network-fetch tests share `QueuedStubURLProtocol`'s
// static state (URLProtocol registration is class-level). Without
// serialization, two tests set the queue or handler at the same time and one
// of them ends up routing its URLSession call through the other's stub.
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
    func configReturnsFetchedValues() async throws {
        let expected = AppConfig(
            posthogApiKey: "phc_test_key",
            posthogHost: "https://test.posthog.com",
            requestOMaticUrl: "https://test.example.com/request",
            apiBaseUrl: "https://test.api.wxyc.org"
        )

        QueuedStubURLProtocol.setBody(try JSONEncoder().encode(expected))
        let session = QueuedStubURLProtocol.makeSession()

        let configuration = AppConfiguration(session: session)
        let config = await configuration.config()

        #expect(config == expected)
    }

    @Test("config returns defaults when network fails")
    func configReturnsDefaultsOnNetworkFailure() async {
        let session = QueuedStubURLProtocol.session { _ in
            throw URLError(.notConnectedToInternet)
        }

        let configuration = AppConfiguration(session: session)
        let config = await configuration.config()

        #expect(config == AppConfiguration.defaults)
    }

    @Test("config caches the fetched result")
    func configCachesFetchedResult() async throws {
        let expected = AppConfig(
            posthogApiKey: "phc_cached",
            posthogHost: "https://cached.posthog.com",
            requestOMaticUrl: "https://cached.example.com/request",
            apiBaseUrl: "https://cached.api.wxyc.org"
        )

        QueuedStubURLProtocol.setBody(try JSONEncoder().encode(expected))
        let session = QueuedStubURLProtocol.makeSession()

        let configuration = AppConfiguration(session: session)
        _ = await configuration.config()
        _ = await configuration.config()

        #expect(QueuedStubURLProtocol.capturedRequests().count == 1)
    }

    @Test("config returns defaults on non-200 status code")
    func configReturnsDefaultsOnBadStatusCode() async {
        QueuedStubURLProtocol.setResponse(statusCode: 500)
        let session = QueuedStubURLProtocol.makeSession()

        let configuration = AppConfiguration(session: session)
        let config = await configuration.config()

        #expect(config == AppConfiguration.defaults)
    }

    @Test("config returns defaults on malformed JSON")
    func configReturnsDefaultsOnMalformedJson() async {
        QueuedStubURLProtocol.setBody(Data("not json".utf8))
        let session = QueuedStubURLProtocol.makeSession()

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
        QueuedStubURLProtocol.setResponses([
            (401, Data()),
            (200, Data(#"{"discogsApiKey": "test-key", "discogsApiSecret": "test-secret"}"#.utf8)),
        ])
        let session = QueuedStubURLProtocol.makeSession()

        let tokenProvider = RecordingTokenProvider(
            initialToken: "stale-token",
            refreshedToken: "fresh-token"
        )
        let configuration = AppConfiguration(session: session)
        let secrets = await configuration.fetchSecrets(tokenProvider: tokenProvider)

        #expect(secrets?.discogsApiKey == "test-key")
        #expect(secrets?.discogsApiSecret == "test-secret")
        #expect(await tokenProvider.reauthenticateCallCount == 1)
        let capturedAuthorizationHeaders = QueuedStubURLProtocol.capturedRequests()
            .map { $0.value(forHTTPHeaderField: "Authorization") }
        #expect(capturedAuthorizationHeaders.count == 2)
        #expect(capturedAuthorizationHeaders[0] == "Bearer stale-token")
        #expect(capturedAuthorizationHeaders[1] == "Bearer fresh-token")
    }

    @Test("fetchSecrets returns nil on a persistent non-2xx response")
    func fetchSecretsReturnsNilOnServerError() async {
        QueuedStubURLProtocol.setResponse(statusCode: 500)
        let session = QueuedStubURLProtocol.makeSession()

        let tokenProvider = RecordingTokenProvider(
            initialToken: "stale-token",
            refreshedToken: "fresh-token"
        )
        let configuration = AppConfiguration(session: session)
        let secrets = await configuration.fetchSecrets(tokenProvider: tokenProvider)

        #expect(secrets == nil)
    }
}
