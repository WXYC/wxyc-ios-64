//
//  TouringSoonModelTests.swift
//  Concerts
//
//  Coverage for the Touring Soon data holder: pagination exhaust, request
//  parameters, load lifecycle, and the filtered/venue-group projections. Driven
//  by `StubConcertsFetcher` with an injected fixed clock.
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import Concerts
import ConcertsTesting

/// A file-private Sendable error for the failure path.
private struct StubFetchError: Error {}

/// Builds a station-zone day (noon) so the injected `now` is deterministic.
private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
    return calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth, hour: 12)) ?? .distantPast
}

/// Builds one page of a paginated response.
private func page(_ concerts: [Concert], number: Int, limit: Int = 100, hasMore: Bool?) -> ConcertsResponse {
    ConcertsResponse(
        concerts: concerts,
        pagination: PaginationInfo(page: number, limit: limit, total: nil, hasMore: hasMore)
    )
}

/// The injected fixed clock. A nonisolated top-level constant so the model's
/// `@Sendable` `now` closure can capture it.
private let fixedNow = day(2026, 8, 1)

@Suite("TouringSoonModel")
@MainActor
struct TouringSoonModelTests {

    private func makeModel(_ fetcher: any ConcertsFetching) -> TouringSoonModel {
        TouringSoonModel(fetcher: fetcher, now: { fixedNow })
    }

    // MARK: - Load lifecycle

    @Test("A single-page load populates the window and reaches .loaded")
    func loadsSinglePage() async {
        let concerts = [Concert.stub(id: 1), Concert.stub(id: 2)]
        let model = makeModel(StubConcertsFetcher(pages: [page(concerts, number: 1, hasMore: false)]))

        await model.load()

        #expect(model.phase == .loaded)
        #expect(model.allConcerts.map(\.id) == [1, 2])
    }

    @Test("A failed load with no cached rows reaches .failed")
    func failedLoad() async {
        let model = makeModel(StubConcertsFetcher(error: StubFetchError()))

        await model.load()

        #expect(model.phase == .failed)
        #expect(model.allConcerts.isEmpty)
    }

    // MARK: - Request parameters

    @Test("Requests are curated, from=today, limit=100")
    func requestParameters() async {
        let stub = StubConcertsFetcher(pages: [page([Concert.stub()], number: 1, hasMore: false)])
        let model = makeModel(stub)

        await model.load()

        let first = stub.requests.first
        #expect(first?.curated == true)
        #expect(first?.from == fixedNow)
        #expect(first?.to == nil)
        #expect(first?.limit == 100)
    }

    // MARK: - Pagination exhaust

    @Test("Follows hasMore across pages and concatenates them in order")
    func exhaustsPagesViaHasMore() async {
        let stub = StubConcertsFetcher(pages: [
            page([Concert.stub(id: 1)], number: 1, hasMore: true),
            page([Concert.stub(id: 2)], number: 2, hasMore: true),
            page([Concert.stub(id: 3)], number: 3, hasMore: false),
        ])
        let model = makeModel(stub)

        await model.load()

        #expect(stub.requests.map(\.page) == [1, 2, 3])
        #expect(model.allConcerts.map(\.id) == [1, 2, 3])
        #expect(model.phase == .loaded)
    }

    @Test("Stops at the page cap and still surfaces what it collected")
    func stopsAtPageCap() async {
        // Every page claims there's more, so only the safety cap can end the loop.
        let pages = (1...TouringSoonModel.pageCap).map {
            page([Concert.stub(id: $0)], number: $0, hasMore: true)
        }
        let stub = StubConcertsFetcher(pages: pages)
        let model = makeModel(stub)

        await model.load()

        #expect(stub.requests.count == TouringSoonModel.pageCap)
        #expect(model.allConcerts.count == TouringSoonModel.pageCap)
        #expect(model.phase == .loaded)
    }

    // MARK: - hasMorePages fallback (server omits hasMore)

    @Test("hasMorePages prefers the server flag when present")
    func hasMorePagesPrefersFlag() {
        #expect(TouringSoonModel.hasMorePages(
            PaginationInfo(page: 1, limit: 100, total: nil, hasMore: true), lastPageCount: 0))
        #expect(!TouringSoonModel.hasMorePages(
            PaginationInfo(page: 1, limit: 100, total: nil, hasMore: false), lastPageCount: 100))
    }

    @Test("hasMorePages falls back to a full page implying more when the flag is absent")
    func hasMorePagesFallback() {
        // Full page → maybe more.
        #expect(TouringSoonModel.hasMorePages(
            PaginationInfo(page: 1, limit: 100, total: nil, hasMore: nil), lastPageCount: 100))
        // Short page → done.
        #expect(!TouringSoonModel.hasMorePages(
            PaginationInfo(page: 1, limit: 100, total: nil, hasMore: nil), lastPageCount: 9))
    }

    // MARK: - Projections

    @Test("filtered applies the current facet state over the window")
    func filteredAppliesFacets() async {
        let cradle = Venue.stub(id: 3, name: "Cat's Cradle", city: "Carrboro")
        let motorco = Venue.stub(id: 7, name: "Motorco", city: "Durham")
        let concerts = [
            Concert.stub(id: 1, venue: cradle, startsOn: day(2026, 8, 1)),
            Concert.stub(id: 2, venue: motorco, startsOn: day(2026, 8, 1)),
        ]
        let model = makeModel(StubConcertsFetcher(pages: [page(concerts, number: 1, hasMore: false)]))
        await model.load()

        #expect(model.filtered.count == 2)
        model.filter.selectedVenueIDs = [3]
        #expect(model.filtered.map(\.id) == [1])
    }

    @Test("venueGroups reflects the distinct venues in the loaded window")
    func venueGroupsDerived() async {
        let cradle = Venue.stub(id: 3, name: "Cat's Cradle", city: "Carrboro")
        let motorco = Venue.stub(id: 7, name: "Motorco", city: "Durham")
        let concerts = [
            Concert.stub(id: 1, venue: cradle),
            Concert.stub(id: 2, venue: motorco),
            Concert.stub(id: 3, venue: cradle), // repeat venue
        ]
        let model = makeModel(StubConcertsFetcher(pages: [page(concerts, number: 1, hasMore: false)]))
        await model.load()

        #expect(model.venueGroups.map(\.region) == ["Chapel Hill–Carrboro", "Durham"])
        #expect(model.venueGroups.first?.venues.count == 1) // Cat's Cradle once
    }
}
