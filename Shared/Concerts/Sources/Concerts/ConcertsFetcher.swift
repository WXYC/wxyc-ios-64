//
//  ConcertsFetcher.swift
//  Concerts
//
//  Fetch layer for Backend-Service's `GET /concerts` Touring Soon read API
//  (WXYC/Backend-Service#1603 / #1606, `wxyc-shared/api.yaml`). Mirrors
//  the request-building + anonymous-session-auth convention used by
//  `Metadata.PlaycutMetadataService`: an optional `SessionTokenProvider` supplies
//  the `Authorization: Bearer <token>` header for the anonymous session the
//  endpoint requires (`requirePermissions({})` on the backend).
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Core

/// Fetches upcoming concerts from Backend-Service's `GET /concerts`.
///
/// The endpoint windows on `starts_on` (the venue-local calendar date), orders
/// by `starts_on` ascending, and paginates. `curated=true` narrows to concerts
/// whose headliner resolved to a WXYC catalog artist. Auth is an anonymous
/// session bearer token, supplied by an optional ``Core/SessionTokenProvider``.
public final class ConcertsFetcher: Sendable {

    /// Errors surfaced by the fetcher.
    public enum ConcertsError: Error, Equatable {
        /// The request URL could not be constructed from the base URL + params.
        case invalidURL
    }

    private let baseURL: URL
    private let session: URLSession
    private let tokenProvider: SessionTokenProvider?

    /// Creates a concerts fetcher.
    ///
    /// - Parameters:
    ///   - baseURL: Backend-Service base URL. Defaults to `https://api.wxyc.org`.
    ///   - session: URLSession to issue requests on. Defaults to `.shared`.
    ///   - tokenProvider: Supplies the anonymous-session bearer token. When
    ///     `nil`, the request is issued unauthenticated (useful in tests behind
    ///     a stub `URLProtocol`).
    public init(
        baseURL: URL = URL(string: "https://api.wxyc.org")!,
        session: URLSession = .shared,
        tokenProvider: SessionTokenProvider? = nil
    ) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
    }

    /// Fetches one page of concerts.
    ///
    /// - Parameters:
    ///   - curated: When `true`, only concerts with a resolved catalog headliner.
    ///   - from: Inclusive lower bound on `starts_on`. When `nil`, the server
    ///     defaults to today (America/New_York).
    ///   - to: Inclusive upper bound on `starts_on`. When `nil`, unbounded.
    ///   - page: 1-indexed page number. Defaults to 1.
    ///   - limit: Page size (server caps at 100). Defaults to 50.
    /// - Returns: The decoded ``ConcertsResponse`` (concerts + pagination).
    public func fetchConcerts(
        curated: Bool = false,
        from: Date? = nil,
        to: Date? = nil,
        page: Int = 1,
        limit: Int = 50
    ) async throws -> ConcertsResponse {
        var items: [URLQueryItem] = []
        if curated {
            items.append(URLQueryItem(name: "curated", value: "true"))
        }
        if let from {
            items.append(URLQueryItem(name: "from", value: Self.dateParam(from)))
        }
        if let to {
            items.append(URLQueryItem(name: "to", value: Self.dateParam(to)))
        }
        items.append(URLQueryItem(name: "page", value: String(page)))
        items.append(URLQueryItem(name: "limit", value: String(limit)))

        var components = URLComponents(
            url: baseURL.appending(path: "concerts"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = items
        guard let url = components?.url else {
            throw ConcertsError.invalidURL
        }

        var request = URLRequest(url: url)
        if let tokenProvider {
            let token = try await tokenProvider.token()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        try (response as? HTTPURLResponse)?.validateSuccessStatus()
        return try JSONDecoder.shared.decode(ConcertsResponse.self, from: data)
    }

    /// Formats a `Date` as the `yyyy-MM-dd` `starts_on` value the endpoint
    /// windows on, in the station (venue) zone so "today" matches the server's
    /// America/New_York boundary rather than the device's zone. Reuses
    /// ``Concert/dateParser`` — the same fixed-locale, station-zone `yyyy-MM-dd`
    /// formatter the model decodes `starts_on` with — so the request window and
    /// the decoded day can never drift apart.
    private static func dateParam(_ date: Date) -> String {
        Concert.dateParser.string(from: date)
    }
}
