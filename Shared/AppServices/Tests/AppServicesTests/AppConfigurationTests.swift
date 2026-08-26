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

    @Test("defaults ships the Donate row dark")
    func defaultsPinsDonateDisabled() {
        // `config()` returns `defaults` on every failure path — non-200,
        // thrown error — so this is what cold launch, airplane mode, and a
        // backend blip render. DonateRowModel also resolves nil to hidden, so
        // this pin is defense-in-depth rather than the sole guarantee — but it
        // keeps lighting up a deliberate change that turns this test red
        // first.
        #expect(AppConfiguration.defaults.donateEnabled == false)
    }

    // `keychainAccessGroup` is deliberately not pinned to a literal here.
    //
    // It used to be, and the pin is what let #996 ship: the assertion compared
    // one hand-written copy of the group against another hand-written copy of
    // the same group, which holds for any value — including the wrong one it
    // was actually pinning. The real group is `$(AppIdentifierPrefix)`-derived
    // and differs per target, so no literal can be right everywhere. Coverage
    // now lives in KeychainAccessGroupTests, against the resolver.

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

    // MARK: - Donate Fields

    @Test("config decodes a response that predates the donate fields")
    func configDecodesResponseMissingDonateFields() async throws {
        // The cascade guard, and the reason both donate fields are Optional.
        // Non-optional properties would make `JSONDecoder.decode` throw against
        // any backend that doesn't serve them yet — and `config()` catches that
        // by returning `defaults` wholesale, silently discarding the remote
        // PostHog key and apiBaseUrl along with the fields it was missing. A
        // backend rollback, a stale 3600s cached response, or simply shipping
        // iOS before Backend-Service deploys all trigger that path.
        QueuedStubURLProtocol.setBody(Data("""
        {
          "posthogApiKey": "phc_remote",
          "posthogHost": "https://remote.posthog.com",
          "requestOMaticUrl": "https://remote.example.com/request",
          "apiBaseUrl": "https://remote.api.wxyc.org"
        }
        """.utf8))
        let session = QueuedStubURLProtocol.makeSession()

        let config = await AppConfiguration(session: session).config()

        #expect(config.posthogApiKey == "phc_remote")
        #expect(config.apiBaseUrl == "https://remote.api.wxyc.org")
        #expect(config.donateUrl == nil)
        #expect(config.donateEnabled == nil)
    }

    @Test("config decodes the donate fields when the backend serves them")
    func configDecodesDonateFields() async throws {
        QueuedStubURLProtocol.setBody(Data("""
        {
          "posthogApiKey": "phc_remote",
          "posthogHost": "https://remote.posthog.com",
          "requestOMaticUrl": "https://remote.example.com/request",
          "apiBaseUrl": "https://remote.api.wxyc.org",
          "donateUrl": "https://example.littlegreenlight.com/lglforms/donate",
          "donateEnabled": true
        }
        """.utf8))
        let session = QueuedStubURLProtocol.makeSession()

        let config = await AppConfiguration(session: session).config()

        #expect(config.donateUrl == "https://example.littlegreenlight.com/lglforms/donate")
        #expect(config.donateEnabled == true)
    }

    @Test("config decodes donateEnabled false — the deploy-time kill switch")
    func configDecodesDonateDisabled() async throws {
        QueuedStubURLProtocol.setBody(Data("""
        {
          "posthogApiKey": "phc_remote",
          "posthogHost": "https://remote.posthog.com",
          "requestOMaticUrl": "https://remote.example.com/request",
          "apiBaseUrl": "https://remote.api.wxyc.org",
          "donateUrl": "https://example.littlegreenlight.com/lglforms/donate",
          "donateEnabled": false
        }
        """.utf8))
        let session = QueuedStubURLProtocol.makeSession()

        let config = await AppConfiguration(session: session).config()

        #expect(config.donateEnabled == false)
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
