//
//  OnTourConcertsE2ETests.swift
//  ConcertsTests
//
//  End-to-end coverage for the On Tour fetch path against the real
//  Backend-Service `GET /concerts`. Reproduces `Singletonia`'s construction
//  order — a `ConcertsFetcher` built with a `DeferredSessionTokenProvider`
//  whose resolver reads `nil` at first (as `MusicShareKit.authService` does
//  before `MusicShareKit.configure(...)` runs), then wired to a live provider —
//  and proves an authenticated round trip decodes a 200. Guards the nil-capture
//  regression that left every `/concerts` request unauthenticated (401).
//
//  Hits api.wxyc.org, so it is `.e2e`-tagged and skipped unless `RUN_E2E=1`.
//
//  Created by Jake Bromberg on 07/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
import Core
import os
@testable import Concerts

@Suite(
    "On Tour Concerts E2E",
    .serialized,
    .tags(.e2e),
    .disabled(if: ProcessInfo.processInfo.environment["RUN_E2E"] != "1")
)
struct OnTourConcertsE2ETests {

    private let baseURL = URL(string: "https://api.wxyc.org")!

    @Test("On Tour fetches real concerts through a provider wired up after the fetcher is built")
    func onTourFetchesRealConcertsThroughDeferredProvider() async throws {
        // Reproduce Singletonia's construction order: the fetcher is built with a
        // DeferredSessionTokenProvider whose resolver returns nil at first —
        // exactly as `MusicShareKit.authService` reads nil before
        // `MusicShareKit.configure(...)` has run — and only afterwards does the
        // real provider become available. Before the fix, a fetcher built at this
        // point captured that nil permanently, so every /concerts request went out
        // unauthenticated and the server returned 401.
        let box = ProviderBox()
        let fetcher = ConcertsFetcher(
            tokenProvider: DeferredSessionTokenProvider { box.provider }
        )

        // "configure()": the real anonymous-session provider is now wired in. A
        // direct capture would have missed this; the deferred resolver picks it up.
        box.provider = RealAnonymousSessionProvider(
            baseURL: baseURL,
            session: URLSession(configuration: .ephemeral)
        )

        let response = try await fetcher.fetchConcerts(curated: true, page: 1, limit: 5)

        // A decoded 200 is the proof the authenticated round trip worked end to
        // end (sign-in → JWT exchange → bearer-authed GET /concerts → decode). The
        // concert list itself varies with the live booking window, so assert on the
        // pagination echo, which the endpoint always returns.
        #expect(response.pagination.page == 1)
        #expect(response.pagination.limit == 5)
    }
}

/// Thread-safe nil-then-set holder standing in for `MusicShareKit.authService`
/// flipping from `nil` (pre-`configure`) to a live provider. Uses a lock rather
/// than an actor because `DeferredSessionTokenProvider`'s resolver is a
/// synchronous `@Sendable () -> SessionTokenProvider?`.
private final class ProviderBox: Sendable {
    private let state = OSAllocatedUnfairLock<(any SessionTokenProvider)?>(initialState: nil)

    var provider: (any SessionTokenProvider)? {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }
}

/// A `SessionTokenProvider` backed by a real anonymous session against
/// Backend-Service: POST `/auth/sign-in/anonymous` for a session token, then GET
/// `/auth/token` to exchange it for a JWT — the same two-step the app's
/// `AuthenticationService` performs. `reauthenticate(previousToken:)` re-runs the
/// exchange, mirroring a forced refresh after a rejected token.
private struct RealAnonymousSessionProvider: SessionTokenProvider {
    let baseURL: URL
    let session: URLSession

    func token() async throws -> String {
        try await mintJWT()
    }

    func reauthenticate(previousToken _: String) async throws -> String {
        try await mintJWT()
    }

    private func mintJWT() async throws -> String {
        // 1. Anonymous sign-in → 32-char session token.
        var signIn = URLRequest(url: baseURL.appending(path: "auth/sign-in/anonymous"))
        signIn.httpMethod = "POST"
        signIn.setValue("application/json", forHTTPHeaderField: "Content-Type")
        signIn.setValue(baseURL.absoluteString, forHTTPHeaderField: "Origin")
        signIn.httpBody = Data("{}".utf8)
        let (signInData, signInResponse) = try await session.data(for: signIn)
        try (signInResponse as? HTTPURLResponse)?.validateSuccessStatus()
        let sessionToken = try JSONDecoder().decode(TokenEnvelope.self, from: signInData).token

        // 2. Exchange the session token → JWT (the only token /proxy and /concerts accept).
        var exchange = URLRequest(url: baseURL.appending(path: "auth/token"))
        exchange.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        exchange.setValue(baseURL.absoluteString, forHTTPHeaderField: "Origin")
        let (exchangeData, exchangeResponse) = try await session.data(for: exchange)
        try (exchangeResponse as? HTTPURLResponse)?.validateSuccessStatus()
        return try JSONDecoder().decode(TokenEnvelope.self, from: exchangeData).token
    }
}

/// The `{ "token": "…" }` envelope both `/auth/sign-in/anonymous` and
/// `/auth/token` return.
private struct TokenEnvelope: Decodable {
    let token: String
}

extension Tag {
    @Tag static var e2e: Self
}
