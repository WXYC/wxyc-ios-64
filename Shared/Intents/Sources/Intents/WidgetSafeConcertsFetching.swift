//
//  WidgetSafeConcertsFetching.swift
//  Intents
//
//  The `ConcertsFetching` default `AppIntentsDependencies.registerForWidget()`
//  registers. The NowPlayingWidget extension process has no business making
//  its own concerts network requests, so both methods resolve to an empty
//  result rather than trapping on an unregistered `@Dependency` (#751) or
//  reaching the network.
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Concerts
import Foundation

/// Resolves every fetch to an empty result rather than issuing a real
/// network request.
struct WidgetSafeConcertsFetching: ConcertsFetching {
    /// The single failure mode `fetchConcert(id:)` reports -- the same shape
    /// callers already handle for a real fetcher's 404.
    enum Error: Swift.Error {
        case unavailable
    }

    func fetchConcerts(
        curated: Bool,
        from: Date?,
        to: Date?,
        page: Int,
        limit: Int
    ) async throws -> ConcertsResponse {
        ConcertsResponse(
            concerts: [],
            pagination: PaginationInfo(page: page, limit: limit, total: 0, hasMore: false)
        )
    }

    func fetchConcert(id: Int) async throws -> Concert {
        throw Error.unavailable
    }
}
