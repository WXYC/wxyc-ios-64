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

    /// This double only exercises the single-flight `load()` path; single-concert
    /// lookup is never called here, so it throws to satisfy the protocol.
    func fetchConcert(id: Int) async throws -> Concert {
        throw StubFetchError()
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

    @Test("A load issued while one is already in flight coalesces onto it (single fetch)")
    func overlappingLoadsCoalesce() async {
        let fetcher = GatedConcertsFetcher(
            response: page([Concert.stub(id: 1)], number: 1, hasMore: false)
        )
        let model = makeModel(fetcher)

        // Start the first load and wait until it has parked inside the fetcher.
        async let first: Void = model.load()
        await fetcher.waitUntilParked()

        // A second load while the first is in flight coalesces onto it: it awaits
        // the same task rather than starting a new fetch, so it can't be awaited
        // before the release without deadlocking.
        async let second: Void = model.load()

        // Let the single in-flight load finish; both awaiters observe it.
        fetcher.release()
        await first
        await second

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

    @Test("availableGenres is the distinct genres in the window, de-duplicated and sorted")
    func availableGenresDerived() async {
        let concerts = [
            Concert.stub(id: 1, genres: ["Rock", "Folk World & Country"]),
            Concert.stub(id: 2, genres: ["Electronic"]),
            Concert.stub(id: 3, genres: ["Rock"]),      // duplicate genre
            Concert.stub(id: 4, genres: nil),            // no genres — contributes nothing
        ]
        let model = makeModel(StubConcertsFetcher(pages: [page(concerts, number: 1, hasMore: false)]))
        await model.load()

        #expect(model.availableGenres == ["Electronic", "Folk World & Country", "Rock"])
    }

    @Test("availableGenres is empty when no show in the window carries a genre")
    func availableGenresEmptyWhenNoGenres() async {
        let concerts = [Concert.stub(id: 1, genres: nil), Concert.stub(id: 2, genres: [])]
        let model = makeModel(StubConcertsFetcher(pages: [page(concerts, number: 1, hasMore: false)]))
        await model.load()

        #expect(model.availableGenres.isEmpty)
    }

    // MARK: - Deep-link resolution (#537)

    @Test("resolveConcert finds an id already in the loaded window (.window)")
    func resolvesInWindowConcert() async {
        let concerts = [Concert.stub(id: 1), Concert.stub(id: 4821), Concert.stub(id: 2)]
        let model = makeModel(StubConcertsFetcher(pages: [page(concerts, number: 1, hasMore: false)]))

        // No explicit load(): resolveConcert drives the initial fetch itself.
        let resolution = await model.resolveConcert(id: 4821)

        #expect(resolution == .window(Concert.stub(id: 4821)))
        #expect(resolution.concert?.id == 4821)
    }

    @Test("resolveConcert falls back to a by-id fetch when the id is outside the window (.byID)")
    func resolvesByIDOutsideWindow() async {
        let outOfWindow = Concert.stub(id: 9001)
        let stub = StubConcertsFetcher(
            pages: [page([Concert.stub(id: 1)], number: 1, hasMore: false)],
            concertsByID: [9001: outOfWindow]
        )
        let model = makeModel(stub)

        let resolution = await model.resolveConcert(id: 9001)

        #expect(resolution == .byID(outOfWindow))
        #expect(stub.concertIDRequests == [9001])
    }

    @Test("resolveConcert reports a miss when neither the window nor a by-id fetch has it (.missed)")
    func missesWhenUnknown() async {
        let stub = StubConcertsFetcher(
            pages: [page([Concert.stub(id: 1)], number: 1, hasMore: false)]
        )
        let model = makeModel(stub)

        let resolution = await model.resolveConcert(id: 404)

        #expect(resolution == .missed)
        #expect(resolution.concert == nil)
        // It tried the by-id rung before giving up.
        #expect(stub.concertIDRequests == [404])
    }

    @Test("resolveConcert reaches the by-id rung when the window is empty")
    func resolvesByIDWhenWindowEmpty() async {
        // An empty window (no upcoming curated shows) with the target only
        // answerable by a single-id lookup mirrors a cold launch from a share
        // link for a show that isn't in the loaded list.
        let target = Concert.stub(id: 4821)
        let stub = StubConcertsFetcher(pages: [], concertsByID: [4821: target])
        let model = makeModel(stub)

        let resolution = await model.resolveConcert(id: 4821)

        #expect(resolution == .byID(target))
    }

    @Test("resolveConcert awaits an in-flight load instead of racing past it into a by-id fetch")
    func resolveCoalescesWithInFlightLoad() async {
        // Cold-launch shape: the tab's own load() and the deep-link
        // resolveConcert() run concurrently. The gated fetcher holds the load in
        // flight; the resolver must await that load and find the id in the
        // now-loaded window — not no-op past an empty window into a by-id fetch
        // the backend can't answer yet. GatedConcertsFetcher.fetchConcert throws,
        // mirroring that unavailability, so a resolver that reaches the by-id rung
        // here reports `.missed` (the failure this guards against).
        let target = Concert.stub(id: 4821)
        let fetcher = GatedConcertsFetcher(
            response: page([Concert.stub(id: 1), target, Concert.stub(id: 2)], number: 1, hasMore: false)
        )
        let model = makeModel(fetcher)

        // Start the tab's load and wait until it has parked inside the fetcher.
        async let firstLoad: Void = model.load()
        await fetcher.waitUntilParked()

        // Kick off the deep-link resolve and let it run up to its suspension while
        // the load is still parked (so it observes the not-yet-populated window).
        async let resolution = model.resolveConcert(id: 4821)
        await Task.yield()

        // Release the single in-flight fetch; both awaiters observe the window.
        fetcher.release()
        await firstLoad
        let resolved = await resolution

        #expect(resolved == .window(target))
        #expect(fetcher.callCount == 1)
    }

    @Test("ConcertResolution exposes stable analytics labels")
    func resolutionAnalyticsLabels() {
        #expect(ConcertResolution.window(Concert.stub(id: 1)).analyticsLabel == "window")
        #expect(ConcertResolution.byID(Concert.stub(id: 1)).analyticsLabel == "byID")
        #expect(ConcertResolution.missed.analyticsLabel == "missed")
    }
}
