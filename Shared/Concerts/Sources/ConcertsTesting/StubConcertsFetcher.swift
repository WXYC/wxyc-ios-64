//
//  StubConcertsFetcher.swift
//  ConcertsTesting
//
//  A canned ``ConcertsFetching`` for driving ``OnTourModel`` in tests and
//  SwiftUI previews. Returns pre-built pages in page order, records each request
//  so pagination behavior can be asserted, and can be primed to throw.
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Synchronization
import Concerts

/// A single recorded `fetchConcerts` invocation.
public struct ConcertPageRequest: Sendable, Equatable {
    public let curated: Bool
    public let from: Date?
    public let to: Date?
    public let page: Int
    public let limit: Int
}

/// A stub concerts fetcher that replays a fixed list of pages.
///
/// Page N (1-indexed) returns `pages[N - 1]`. A request past the last canned page
/// returns an empty page with `hasMore == false`, so an over-eager pagination
/// loop terminates rather than hanging. Priming with an error makes every call
/// throw.
public final class StubConcertsFetcher: ConcertsFetching {

    private let pages: [ConcertsResponse]
    private let error: (any Error & Sendable)?
    private let concertsByID: [Int: Concert]
    private let recorded = Mutex<[ConcertPageRequest]>([])
    private let recordedIDs = Mutex<[Int]>([])

    /// Creates a fetcher that replays `pages` in order.
    ///
    /// - Parameters:
    ///   - pages: The list responses `fetchConcerts` replays, page N → `pages[N-1]`.
    ///   - concertsByID: The concerts `fetchConcert(id:)` can answer, keyed by id.
    ///     An id absent from this map is treated as a 404 (throws), which drives
    ///     the resolution ladder's `.missed` rung.
    public init(pages: [ConcertsResponse], concertsByID: [Int: Concert] = [:]) {
        self.pages = pages
        self.error = nil
        self.concertsByID = concertsByID
    }

    /// Creates a fetcher whose every call — list *and* by-id — throws `error`.
    public init(error: any Error & Sendable) {
        self.pages = []
        self.error = error
        self.concertsByID = [:]
    }

    /// The list requests received so far, in call order.
    public var requests: [ConcertPageRequest] {
        recorded.withLock { $0 }
    }

    /// The concert ids passed to `fetchConcert(id:)` so far, in call order.
    public var concertIDRequests: [Int] {
        recordedIDs.withLock { $0 }
    }

    public func fetchConcerts(
        curated: Bool,
        from: Date?,
        to: Date?,
        page: Int,
        limit: Int
    ) async throws -> ConcertsResponse {
        recorded.withLock {
            $0.append(ConcertPageRequest(curated: curated, from: from, to: to, page: page, limit: limit))
        }
        if let error {
            throw error
        }
        let index = page - 1
        guard pages.indices.contains(index) else {
            return ConcertsResponse(
                concerts: [],
                pagination: PaginationInfo(page: page, limit: limit, total: nil, hasMore: false)
            )
        }
        return pages[index]
    }

    public func fetchConcert(id: Int) async throws -> Concert {
        recordedIDs.withLock { $0.append(id) }
        if let error {
            throw error
        }
        guard let concert = concertsByID[id] else {
            // Mimic the endpoint's 404 for an unknown id, matching the concrete
            // fetcher's `validateSuccessStatus()` failure so the ladder degrades
            // to `.missed` the same way in tests as in production.
            throw URLError(.badServerResponse)
        }
        return concert
    }
}
