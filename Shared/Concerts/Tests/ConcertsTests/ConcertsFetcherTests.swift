//
//  ConcertsFetcherTests.swift
//  ConcertsTests
//
//  Tests the request the fetch layer issues against `GET /concerts`: the query
//  params (`curated`, `from`/`to`, pagination) and the anonymous-session bearer
//  header, plus that it decodes the response envelope. Uses a stub URLProtocol
//  so no network is touched.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
import Core
@testable import Concerts

/// A `SessionTokenProvider` returning a fixed token, so the fetcher's bearer
/// header can be asserted.
private struct FixedTokenProvider: SessionTokenProvider {
    let value: String
    func token() async throws -> String { value }
}

@Suite("ConcertsFetcher", .serialized)
struct ConcertsFetcherTests {

    private static let base = URL(string: "https://api.wxyc.test")!

    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    private static let responseBody = Data("""
    {
        "concerts": [
            {
                "id": 1,
                "venue": { "id": 1, "slug": "cats-cradle", "name": "Cat's Cradle", "city": "Carrboro", "state": "NC", "address": null },
                "starts_on": "2026-08-01",
                "headlining_artist_raw": "Jessica Pratt",
                "status": "on_sale"
            }
        ],
        "pagination": { "page": 1, "limit": 50, "total": 1, "hasMore": false }
    }
    """.utf8)

    private static func queryValue(_ request: URLRequest, _ name: String) -> String? {
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        return components.queryItems?.first { $0.name == name }?.value
    }

    // MARK: - Request shape

    @Test("Hits /concerts with the default pagination params")
    func defaultRequest() async throws {
        StubURLProtocol.setBody(Self.responseBody)
        let fetcher = ConcertsFetcher(baseURL: Self.base, session: Self.makeSession())

        _ = try await fetcher.fetchConcerts()

        let request = try #require(StubURLProtocol.capturedRequest())
        #expect(request.url?.path == "/concerts")
        #expect(Self.queryValue(request, "page") == "1")
        #expect(Self.queryValue(request, "limit") == "50")
        // curated defaults to false → the param is omitted.
        #expect(Self.queryValue(request, "curated") == nil)
        #expect(Self.queryValue(request, "from") == nil)
        #expect(Self.queryValue(request, "to") == nil)
    }

    @Test("Sends curated, from/to window, and pagination when supplied")
    func fullParams() async throws {
        StubURLProtocol.setBody(Self.responseBody)
        let fetcher = ConcertsFetcher(baseURL: Self.base, session: Self.makeSession())

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        let from = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))
        let to = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 31)))

        _ = try await fetcher.fetchConcerts(curated: true, from: from, to: to, page: 2, limit: 25)

        let request = try #require(StubURLProtocol.capturedRequest())
        #expect(Self.queryValue(request, "curated") == "true")
        #expect(Self.queryValue(request, "from") == "2026-08-01")
        #expect(Self.queryValue(request, "to") == "2026-08-31")
        #expect(Self.queryValue(request, "page") == "2")
        #expect(Self.queryValue(request, "limit") == "25")
    }

    // MARK: - Auth

    @Test("Sends the anonymous-session bearer token when a provider is supplied")
    func sendsBearerToken() async throws {
        StubURLProtocol.setBody(Self.responseBody)
        let fetcher = ConcertsFetcher(
            baseURL: Self.base,
            session: Self.makeSession(),
            tokenProvider: FixedTokenProvider(value: "anon-token-123")
        )

        _ = try await fetcher.fetchConcerts()

        let request = try #require(StubURLProtocol.capturedRequest())
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer anon-token-123")
    }

    @Test("Omits the Authorization header when no provider is supplied")
    func omitsAuthHeaderWithoutProvider() async throws {
        StubURLProtocol.setBody(Self.responseBody)
        let fetcher = ConcertsFetcher(baseURL: Self.base, session: Self.makeSession())

        _ = try await fetcher.fetchConcerts()

        let request = try #require(StubURLProtocol.capturedRequest())
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    // MARK: - Decode

    @Test("Decodes the response envelope into concerts + pagination")
    func decodesResponse() async throws {
        StubURLProtocol.setBody(Self.responseBody)
        let fetcher = ConcertsFetcher(baseURL: Self.base, session: Self.makeSession())

        let response = try await fetcher.fetchConcerts()

        #expect(response.concerts.count == 1)
        #expect(response.concerts.first?.headliningArtistRaw == "Jessica Pratt")
        #expect(response.pagination.total == 1)
    }
}
