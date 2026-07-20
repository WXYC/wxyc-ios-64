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

    // MARK: - Error path

    @Test("Throws URLError(.badServerResponse) on a non-2xx response")
    func throwsOnServerError() async throws {
        StubURLProtocol.setResponse(Data("""
        {"error": "Internal Server Error"}
        """.utf8), statusCode: 500)
        let fetcher = ConcertsFetcher(baseURL: Self.base, session: Self.makeSession())

        await #expect(throws: URLError(.badServerResponse)) {
            _ = try await fetcher.fetchConcerts()
        }
    }

    // MARK: - Page-level decode tolerance

    /// A page where one concert carries an empty-string `ticket_url` (the
    /// backend stores `""` verbatim). Regression guard for the "0 concerts
    /// instead of N" bug: a strict `URL(from:)` decode would throw on the empty
    /// string and fail the entire page. Both concerts must still decode.
    private static let pageWithEmptyTicketURL = Data("""
    {
        "concerts": [
            {
                "id": 1,
                "venue": { "id": 1, "slug": "cats-cradle", "name": "Cat's Cradle", "city": "Carrboro", "state": "NC", "address": null },
                "starts_on": "2026-08-01",
                "headlining_artist_raw": "Jessica Pratt",
                "ticket_url": "",
                "status": "on_sale"
            },
            {
                "id": 2,
                "venue": { "id": 2, "slug": "local-506", "name": "Local 506", "city": "Chapel Hill", "state": "NC", "address": null },
                "starts_on": "2026-08-05",
                "headlining_artist_raw": "Juana Molina",
                "ticket_url": "https://www.etix.com/ticket/p/juana-molina",
                "status": "on_sale"
            }
        ],
        "pagination": { "page": 1, "limit": 50, "total": 2, "hasMore": false }
    }
    """.utf8)

    @Test("Decodes the whole page when one concert has an empty ticket_url")
    func decodesPageWithEmptyTicketURL() async throws {
        StubURLProtocol.setBody(Self.pageWithEmptyTicketURL)
        let fetcher = ConcertsFetcher(baseURL: Self.base, session: Self.makeSession())

        let response = try await fetcher.fetchConcerts()

        #expect(response.concerts.count == 2)
        // The bad row decodes with a nil ticketURL rather than failing the page.
        #expect(response.concerts.first?.ticketURL == nil)
        #expect(response.concerts.last?.ticketURL == URL(string: "https://www.etix.com/ticket/p/juana-molina"))
    }

    // MARK: - Single concert lookup (#537)

    /// A bare `Concert` (not the `{concerts,pagination}` envelope) — the shape
    /// `GET /concerts/:id` returns, mirroring conventional REST item lookup.
    private static let singleConcertBody = Data("""
    {
        "id": 4821,
        "venue": { "id": 3, "slug": "cats-cradle", "name": "Cat's Cradle", "city": "Carrboro", "state": "NC", "address": null },
        "starts_on": "2026-08-01",
        "headlining_artist_raw": "Jessica Pratt",
        "status": "on_sale"
    }
    """.utf8)

    @Test("Hits /concerts/<id> and decodes a bare concert")
    func fetchesSingleConcert() async throws {
        StubURLProtocol.setBody(Self.singleConcertBody)
        let fetcher = ConcertsFetcher(baseURL: Self.base, session: Self.makeSession())

        let concert = try await fetcher.fetchConcert(id: 4821)

        let request = try #require(StubURLProtocol.capturedRequest())
        #expect(request.url?.path == "/concerts/4821")
        #expect(concert.id == 4821)
        #expect(concert.headliningArtistRaw == "Jessica Pratt")
    }

    @Test("Sends the anonymous-session bearer token on the single-concert request")
    func singleConcertSendsBearerToken() async throws {
        StubURLProtocol.setBody(Self.singleConcertBody)
        let fetcher = ConcertsFetcher(
            baseURL: Self.base,
            session: Self.makeSession(),
            tokenProvider: FixedTokenProvider(value: "anon-token-123")
        )

        _ = try await fetcher.fetchConcert(id: 4821)

        let request = try #require(StubURLProtocol.capturedRequest())
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer anon-token-123")
    }

    @Test("Throws on a 404 for an unknown concert id")
    func singleConcertThrowsOnNotFound() async throws {
        StubURLProtocol.setResponse(Data("""
        {"error": "Not Found"}
        """.utf8), statusCode: 404)
        let fetcher = ConcertsFetcher(baseURL: Self.base, session: Self.makeSession())

        await #expect(throws: URLError(.badServerResponse)) {
            _ = try await fetcher.fetchConcert(id: 999_999)
        }
    }
}
