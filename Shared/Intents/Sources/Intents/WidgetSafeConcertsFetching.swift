//
//  WidgetSafeConcertsFetching.swift
//  Intents
//
//  The `ConcertsFetching` default `AppIntentsDependencies.registerForWidget()`
//  registers. The NowPlayingWidget extension process has no business making
//  its own concerts network requests, so neither method reaches the network
//  -- but they deliberately do NOT share one "safe empty" shape (#751 review,
//  finding B3):
//
//  `fetchConcert(id:)` throws. Its sole call site
//  (`ConcertEntityQuery+IndexedEntityQuery.swift`'s `reindexEntities(for:)`)
//  wraps it in `try?` and drops the id -- "a Spotlight-requested reindex of a
//  row that's gone isn't an error," the same contract a real fetcher's 404
//  satisfies. Throwing here is harmless.
//
//  `fetchConcerts` also throws, even though its shape (`ConcertsResponse`)
//  could return a technically-successful empty page instead. It must not:
//  `reindexAllEntities()`'s doc comment states the fetch-failure contract
//  explicitly -- "a failed list fetch here propagates (rather than degrading
//  to an empty donation): swallowing it would let a transient network
//  failure look to Spotlight like the app confirms the index is now empty,
//  when the honest answer is ask again later." A widget-process reindex that
//  returned an empty-but-successful page would trip
//  `reindexAllEntities()`'s `guard !concerts.isEmpty else { return }` and
//  report success having donated nothing, which reads to Spotlight as "the
//  app confirms `wxyc.concerts` should be emptied" -- silently evicting rows
//  the app process donated for real. An earlier version of this file got
//  this backwards (threw from `fetchConcert(id:)`, returned empty success
//  from `fetchConcerts`) -- the asymmetry that mattered was inverted.
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Concerts
import Foundation

/// Never reaches the network; both methods throw rather than fabricate a
/// result, so neither an unresolvable single concert nor a failed page fetch
/// can look like a successful empty answer.
struct WidgetSafeConcertsFetching: ConcertsFetching {
    /// The single failure mode both methods report -- the widget process
    /// never issues a real network request, so there is no page or concert
    /// to return.
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
        throw Error.unavailable
    }

    func fetchConcert(id: Int) async throws -> Concert {
        throw Error.unavailable
    }
}
