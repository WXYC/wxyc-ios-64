//
//  ConcertEntityQuery+IndexedEntityQuery.swift
//  Intents
//
//  iOS 27's `IndexedEntityQuery` lets Spotlight ask the app to re-donate
//  entities — row-by-row or wholesale — when it flags a problem with the
//  `wxyc.concerts` index, mirroring `PlaycutEntityQuery+IndexedEntityQuery`.
//  Both handlers resolve concerts through `ConcertsFetching` — the same
//  fetch seam `OnTourModel`/`ToursNearMeQuery` use — and re-donate through
//  `ConcertReindexer`. Both report `SpotlightReindexRequested` through
//  `AnalyticsService` (#445) before resolving anything, matching the playcut
//  handlers, so a reindex ask is visible in PostHog even when nothing ends
//  up donated.
//
//  `reindexAllEntities()` reuses `ToursNearMeQuery.fetchRequestParameters`
//  (curated=true, from today, one page of up to 100) rather than inventing
//  its own notion of "the curated window" — the same definition the
//  "touring near me" Siri intent already fetches against, so the two
//  features' idea of what's current can't drift apart.
//
//  Neither handler routes through `ConcertSpotlightDonationService.reconcile
//  (window:...)` — see `ConcertReindexer`'s doc comment for why the
//  persisted-id diff/eviction that powers the OT-F2 background pass would
//  misfire on a Spotlight-driven reindex ask.
//
//  Gated to Swift 6.4 (the Xcode 27 beta toolchain): `IndexedEntityQuery` is
//  new in the iOS 27 AppIntents swiftinterface and isn't present in stable
//  Xcode 26.5/26.6. Stable builds skip this file entirely; `ConcertEntityQuery`
//  itself is unaffected — see `ConcertEntityQuery.swift`, which declares the
//  `@Dependency` stored properties this extension reads (a Swift extension
//  can't add stored properties, so they can't live here).
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if compiler(>=6.4)
#if !os(watchOS) && !os(tvOS)
import Analytics
import AppIntents
import Concerts
import CoreSpotlight
import Foundation
import Logger

@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
extension ConcertEntityQuery: IndexedEntityQuery {
    /// Re-donates the identified concerts to `wxyc.concerts`.
    ///
    /// Ids `ConcertsFetching.fetchConcert(id:)` can't resolve (a 404 — a
    /// since-cancelled or unknown concert, or a transient fetch failure) are
    /// silently omitted, matching `entities(for:)`'s own drop-unknown-ids
    /// contract — a Spotlight-requested reindex of a row that's gone isn't
    /// an error.
    public func reindexEntities(
        for identifiers: [ConcertID],
        indexDescription: CSSearchableIndexDescription
    ) async throws {
        let rawIDs = identifiers.compactMap(\.concertID)
        Log(.info, category: .general, "Spotlight requested reindexEntities(for:) — \(rawIDs.count) id(s)")
        analytics.capture(SpotlightReindexRequested(kind: "single", rowCount: rawIDs.count))

        var concerts: [Concert] = []
        for id in rawIDs {
            if let concert = try? await concertsFetching.fetchConcert(id: id) {
                concerts.append(concert)
            }
        }
        guard !concerts.isEmpty else { return }
        try await reindexer.donate(concerts)
    }

    /// Re-donates the current curated On Tour window in full, so a rebuilt
    /// or evicted `wxyc.concerts` index gets every still-current concert
    /// back with a freshly computed expiration.
    ///
    /// Unlike `reindexEntities(for:)`, a failed list fetch here propagates
    /// (rather than degrading to an empty donation): swallowing it would let
    /// a transient network failure look to Spotlight like "the app confirms
    /// the index is now empty," when the honest answer is "ask again later."
    public func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        let params = ToursNearMeQuery.fetchRequestParameters(now: Date())
        let response = try await concertsFetching.fetchConcerts(
            curated: params.curated,
            from: params.from,
            to: params.to,
            page: params.page,
            limit: params.limit
        )
        let concerts = response.concerts
        Log(.info, category: .general, "Spotlight requested reindexAllEntities() — \(concerts.count) concert(s)")
        analytics.capture(SpotlightReindexRequested(kind: "all", rowCount: concerts.count))
        guard !concerts.isEmpty else { return }
        try await reindexer.donate(concerts)
    }
}
#endif
#endif
