//
//  ConcertEntityQueryReindexTests.swift
//  WXYCIntents
//
//  Verifies the F3 `IndexedEntityQuery` reindex handlers via a stub
//  `ConcertsFetching` and a spy `ConcertReindexer`, mirroring
//  `PlaycutEntityQueryReindexTests`: `reindexEntities(for:)` donates only ids
//  `ConcertsFetching.fetchConcert(id:)` can resolve (a miss is omitted, not
//  an error), and `reindexAllEntities` re-donates the curated window fetched
//  via `ConcertsFetching.fetchConcerts(curated:...)` — the same
//  `ToursNearMeQuery.fetchRequestParameters` shape the "touring near me"
//  Siri intent already fetches against.
//
//  Gated to Swift 6.4 (the Xcode 27 beta toolchain), matching
//  `ConcertEntityQuery+IndexedEntityQuery.swift`. Each test starts with
//  `guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }`
//  (the `PlaycutEntityQueryReindexTests.swift` precedent) so the suite is a
//  no-op rather than a failure on a host OS below the runtime floor — the
//  beta-toolchain verification for this ticket is a build, not a test run.
//
//  `.serialized`: `AppDependencyManager.shared` is a process-global registry
//  keyed by dependency type, shared across every `@Dependency`-backed
//  AppIntents query in the process — including `PlaycutEntityQueryReindexTests`,
//  which registers its own `any AnalyticsService` the same way. `.serialized`
//  only protects the tests *within* this suite from racing each other; a
//  concurrent run of a different suite that also registers `any
//  AnalyticsService` (there is exactly one other today: the playcut reindex
//  suite) could in principle interleave with this one's add-then-read. That
//  cross-suite risk predates this file — it's inherent to
//  `AppDependencyManager.shared` being a single process-wide registry — and
//  isn't something a single suite's trait can close; flagged here rather
//  than silently ignored.
//
//  Every test also registers a `MockStructuredAnalytics` — `ConcertEntityQuery`'s
//  `analytics` property (#445) is a required `@Dependency`, which traps on
//  access if unregistered.
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if compiler(>=6.4)
import Analytics
import AnalyticsTesting
import AppIntents
import Concerts
import ConcertsTesting
import CoreSpotlight
import Foundation
import Testing
@testable import WXYCIntents

@Suite("ConcertEntityQuery+IndexedEntityQuery (F3 reindex handlers)", .serialized)
struct ConcertEntityQueryReindexTests {
    @Test("reindexEntities donates only ids ConcertsFetching can resolve; a miss is omitted, not an error")
    func reindexEntitiesDonatesOnlyKnownIDs() async throws {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }

        let jessica = Concert.stub(id: 1, headliningArtistRaw: "Jessica Pratt")
        let fetcher = StubConcertsFetcher(pages: [], concertsByID: [1: jessica])
        AppDependencyManager.shared.add(dependency: fetcher as any ConcertsFetching)
        let reindexer = SpyConcertReindexer()
        AppDependencyManager.shared.add(dependency: reindexer as any ConcertReindexer)
        let analytics = MockStructuredAnalytics()
        AppDependencyManager.shared.add(dependency: analytics as any AnalyticsService)

        let jessicaID = try #require(ConcertID(concertID: 1))
        let unknownID = try #require(ConcertID(concertID: 999))
        let query = ConcertEntityQuery()
        try await query.reindexEntities(for: [jessicaID, unknownID], indexDescription: CSSearchableIndexDescription())

        let donated = await reindexer.donatedIDs
        #expect(donated == [1])

        // #445: reports the request count (both ids asked for), not just the
        // ids the fetcher resolved.
        let events = analytics.typedEvents(ofType: SpotlightReindexRequested.self)
        #expect(events.count == 1)
        #expect(events.first?.kind == "single")
        #expect(events.first?.rowCount == 2)
    }

    @Test("reindexEntities with no matches donates nothing")
    func reindexEntitiesEmptyMatchDonatesNothing() async throws {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }

        let fetcher = StubConcertsFetcher(pages: [], concertsByID: [:])
        AppDependencyManager.shared.add(dependency: fetcher as any ConcertsFetching)
        let reindexer = SpyConcertReindexer()
        AppDependencyManager.shared.add(dependency: reindexer as any ConcertReindexer)
        AppDependencyManager.shared.add(dependency: MockStructuredAnalytics() as any AnalyticsService)

        let unknownID = try #require(ConcertID(concertID: 404))
        let query = ConcertEntityQuery()
        try await query.reindexEntities(for: [unknownID], indexDescription: CSSearchableIndexDescription())

        let batches = await reindexer.donatedBatches
        #expect(batches.isEmpty)
    }

    @Test("reindexAllEntities re-donates the curated window fetched via ConcertsFetching")
    func reindexAllEntitiesDonatesCuratedWindow() async throws {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }

        let juana = Concert.stub(id: 1, headliningArtistRaw: "Juana Molina")
        let jessica = Concert.stub(id: 2, headliningArtistRaw: "Jessica Pratt")
        let page = ConcertsResponse(
            concerts: [juana, jessica],
            pagination: PaginationInfo(page: 1, limit: 100, total: 2, hasMore: false)
        )
        let fetcher = StubConcertsFetcher(pages: [page])
        AppDependencyManager.shared.add(dependency: fetcher as any ConcertsFetching)
        let reindexer = SpyConcertReindexer()
        AppDependencyManager.shared.add(dependency: reindexer as any ConcertReindexer)
        let analytics = MockStructuredAnalytics()
        AppDependencyManager.shared.add(dependency: analytics as any AnalyticsService)

        let query = ConcertEntityQuery()
        try await query.reindexAllEntities(indexDescription: CSSearchableIndexDescription())

        let donated = await reindexer.donatedIDs
        #expect(Set(donated) == Set([1, 2]))

        // Reuses `ToursNearMeQuery.fetchRequestParameters`'s notion of "the
        // curated window" rather than inventing a new one.
        let request = try #require(fetcher.requests.first)
        #expect(request.curated == true)
        #expect(request.page == 1)
        #expect(request.limit == ToursNearMeQuery.fetchLimit)

        let events = analytics.typedEvents(ofType: SpotlightReindexRequested.self)
        #expect(events.count == 1)
        #expect(events.first?.kind == "all")
        #expect(events.first?.rowCount == 2)
    }

    @Test("reindexAllEntities against an empty window donates nothing")
    func reindexAllEntitiesEmptyWindowDonatesNothing() async throws {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }

        let emptyPage = ConcertsResponse(
            concerts: [],
            pagination: PaginationInfo(page: 1, limit: 100, total: 0, hasMore: false)
        )
        AppDependencyManager.shared.add(dependency: StubConcertsFetcher(pages: [emptyPage]) as any ConcertsFetching)
        let reindexer = SpyConcertReindexer()
        AppDependencyManager.shared.add(dependency: reindexer as any ConcertReindexer)
        AppDependencyManager.shared.add(dependency: MockStructuredAnalytics() as any AnalyticsService)

        let query = ConcertEntityQuery()
        try await query.reindexAllEntities(indexDescription: CSSearchableIndexDescription())

        let batches = await reindexer.donatedBatches
        #expect(batches.isEmpty)
    }

    @Test("reindexAllEntities propagates a list-fetch failure rather than donating an empty window")
    func reindexAllEntitiesPropagatesFetchFailure() async throws {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }

        AppDependencyManager.shared.add(dependency: StubConcertsFetcher(error: URLError(.timedOut)) as any ConcertsFetching)
        let reindexer = SpyConcertReindexer()
        AppDependencyManager.shared.add(dependency: reindexer as any ConcertReindexer)
        AppDependencyManager.shared.add(dependency: MockStructuredAnalytics() as any AnalyticsService)

        let query = ConcertEntityQuery()
        await #expect(throws: (any Error).self) {
            try await query.reindexAllEntities(indexDescription: CSSearchableIndexDescription())
        }

        let batches = await reindexer.donatedBatches
        #expect(batches.isEmpty)
    }
}

/// Records every `donate(_:)` call's concert ids as a separate batch, so
/// tests can assert both membership and (for the single-id path) that
/// nothing was donated on an empty resolve.
actor SpyConcertReindexer: ConcertReindexer {
    private(set) var donatedBatches: [[Concert]] = []

    var donatedIDs: [Int] {
        donatedBatches.flatMap { $0 }.map(\.id)
    }

    func donate(_ concerts: [Concert]) async throws {
        donatedBatches.append(concerts)
    }
}
#endif
