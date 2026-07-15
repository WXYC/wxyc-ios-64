//
//  OnTourModelTests.swift
//  Concerts
//
//  Coverage for the On Tour data holder: pagination exhaust, request
//  parameters, load lifecycle, and the filtered/venue-group projections. Driven
//  by `StubConcertsFetcher` with an injected fixed clock.
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Synchronization
import Testing
@testable import Concerts
import ConcertsTesting

/// A file-private Sendable error for the failure path.
private struct StubFetchError: Error {}

/// A fetcher that parks inside `fetchConcerts` until ``release()`` is called, so a
/// test can hold one `load()` in flight while it issues a second — exercising the
/// model's single-flight guard. Records how many times it was actually invoked.
private final class GatedConcertsFetcher: ConcertsFetching {
    private struct State {
        var callCount = 0
        var parked = false
        var release: CheckedContinuation<Void, Never>?
        var onParked: (() -> Void)?
    }

    private let response: ConcertsResponse
    private let state = Mutex(State())

    init(response: ConcertsResponse) {
        self.response = response
    }

    var callCount: Int { state.withLock { $0.callCount } }

    func fetchConcerts(
        curated: Bool,
        from: Date?,
        to: Date?,
        page: Int,
        limit: Int
    ) async throws -> ConcertsResponse {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let notifyParked: (() -> Void)? = state.withLock { state in
                state.callCount += 1
                state.release = continuation
                state.parked = true
                let onParked = state.onParked
                state.onParked = nil
                return onParked
            }
            notifyParked?()
        }
        return response
    }

    /// Resolves once a `fetchConcerts` call has parked at the gate.
    func waitUntilParked() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let alreadyParked: Bool = state.withLock {
                if $0.parked { return true }
                $0.onParked = { continuation.resume() }
                return false
            }
            if alreadyParked { continuation.resume() }
        }
    }

    /// Releases the parked `fetchConcerts` call so it returns its response.
    func release() {
        let continuation = state.withLock { state -> CheckedContinuation<Void, Never>? in
            let parked = state.release
            state.release = nil
            state.parked = false
            return parked
        }
        continuation?.resume()
    }
}

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

@Suite("OnTourModel")
@MainActor
struct OnTourModelTests {

    private func makeModel(_ fetcher: any ConcertsFetching) -> OnTourModel {
        OnTourModel(fetcher: fetcher, now: { fixedNow })
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
        // Prime *more* pages than the cap, all claiming `hasMore`, so the cap is
        // the only thing that can end the loop — the stub can't run out first and
        // mask an off-by-one in the cap check.
        let pages = (1...(OnTourModel.pageCap + 2)).map {
            page([Concert.stub(id: $0)], number: $0, hasMore: true)
        }
        let stub = StubConcertsFetcher(pages: pages)
        let model = makeModel(stub)

        await model.load()

        #expect(stub.requests.count == OnTourModel.pageCap)
        #expect(model.allConcerts.count == OnTourModel.pageCap)
        #expect(model.phase == .loaded)
    }

    // MARK: - Single-flight

    @Test("A load issued while one is already in flight is a no-op")
    func overlappingLoadsCoalesce() async {
        let fetcher = GatedConcertsFetcher(
            response: page([Concert.stub(id: 1)], number: 1, hasMore: false)
        )
        let model = makeModel(fetcher)

        // Start the first load and wait until it has parked inside the fetcher.
        async let first: Void = model.load()
        await fetcher.waitUntilParked()

        // A second load while the first is in flight must not start a new fetch.
        await model.load()

        // Let the first load finish.
        fetcher.release()
        await first

        #expect(fetcher.callCount == 1)
        #expect(model.phase == .loaded)
        #expect(model.allConcerts.map(\.id) == [1])
    }

    // MARK: - hasMorePages fallback (server omits hasMore)

    @Test("hasMorePages prefers the server flag when present")
    func hasMorePagesPrefersFlag() {
        #expect(OnTourModel.hasMorePages(
            PaginationInfo(page: 1, limit: 100, total: nil, hasMore: true), lastPageCount: 0))
        #expect(!OnTourModel.hasMorePages(
            PaginationInfo(page: 1, limit: 100, total: nil, hasMore: false), lastPageCount: 100))
    }

    @Test("hasMorePages falls back to a full page implying more when the flag is absent")
    func hasMorePagesFallback() {
        // Full page → maybe more.
        #expect(OnTourModel.hasMorePages(
            PaginationInfo(page: 1, limit: 100, total: nil, hasMore: nil), lastPageCount: 100))
        // Short page → done.
        #expect(!OnTourModel.hasMorePages(
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
