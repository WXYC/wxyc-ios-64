//
//  ConcertsFetching.swift
//  Concerts
//
//  The fetch seam the On Tour model depends on, so the model can be driven
//  by a canned stub in tests and previews without a live network. The production
//  ``ConcertsFetcher`` conforms; test doubles conform in `ConcertsTesting`.
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Fetches a page of concerts from the On Tour read API.
///
/// Extracted from the concrete ``ConcertsFetcher`` purely as a test/preview seam:
/// ``OnTourModel`` holds `any ConcertsFetching`, so a stub can feed it
/// deterministic pages. The single requirement mirrors
/// ``ConcertsFetcher/fetchConcerts(curated:from:to:page:limit:)`` exactly.
public protocol ConcertsFetching: Sendable {

    /// Fetches one page of concerts.
    ///
    /// - Parameters:
    ///   - curated: When `true`, only concerts with a resolved catalog headliner.
    ///   - from: Inclusive lower bound on `starts_on` (station-local), or `nil`.
    ///   - to: Inclusive upper bound on `starts_on`, or `nil` for unbounded.
    ///   - page: 1-indexed page number.
    ///   - limit: Page size (server caps at 100).
    func fetchConcerts(
        curated: Bool,
        from: Date?,
        to: Date?,
        page: Int,
        limit: Int
    ) async throws -> ConcertsResponse

    /// Fetches a single concert by id — the by-id rung of the deep-link
    /// resolution ladder (#537), used when a shared show falls outside the
    /// loaded window. Throws when the id is unknown (the server 404s).
    ///
    /// - Parameter id: The concert's stable id (the `<id>` in `wxyc.org/shows/<id>`).
    func fetchConcert(id: Int) async throws -> Concert
}

extension ConcertsFetcher: ConcertsFetching {}
