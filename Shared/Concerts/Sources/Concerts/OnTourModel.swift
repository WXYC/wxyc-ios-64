//
//  OnTourModel.swift
//  Concerts
//
//  The single data holder for the On Tour tab: fetches the whole curated
//  concert window once, holds it in memory, and exposes a filtered projection
//  recomputed synchronously as the user changes facets — no refetch on filter
//  change (the triangle-shows recipe).
//
//  Concurrency: deliberately `@MainActor`-bound single-screen UI state. Unlike
//  `PlaylistService` (an actor, because the flowsheet feed is shared across
//  app/widget/CarPlay through `CacheCoordinator`), `allConcerts` is UI-thread-only
//  and not shared with extensions. If a widget or watch surface ever needs
//  concerts, the sharing seam is ``ConcertsFetching`` — not this model.
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Logger

/// Fetches, holds, and filters the On Tour concert window.
@MainActor
@Observable
public final class OnTourModel {

    /// The load lifecycle. The error is intentionally not surfaced to the view —
    /// the failure state is generic ("couldn't load"); the underlying error is
    /// logged for diagnostics.
    public enum Phase: Equatable, Sendable {
        case loading
        case loaded
        case failed
    }

    /// Server page size. The endpoint caps at 100; one page covers today's window.
    static let pageSize = 100

    /// Safety ceiling on the pagination loop, so a misbehaving `hasMore` can't
    /// spin forever. Hitting it logs a warning.
    static let pageCap = 10

    /// The current load lifecycle state.
    public private(set) var phase: Phase = .loading

    /// The full fetched window, `starts_on` ascending (the server's order).
    public private(set) var allConcerts: [Concert] = []

    /// The user's facet selections. Mutating this recomputes ``filtered``.
    public var filter = ConcertFilterState()

    private let fetcher: any ConcertsFetching
    private let now: @Sendable () -> Date

    /// Single-flight guard: a load already in flight makes a concurrent ``load()``
    /// a no-op, so an error-state retry that overlaps a tab-reappearance `.task`
    /// (or a foreground refresh racing the initial load) can't kick off a second
    /// pagination sweep. Main-actor isolation makes the check-and-set atomic.
    private var isLoading = false

    /// Creates a model.
    ///
    /// - Parameters:
    ///   - fetcher: The concerts source (production ``ConcertsFetcher``, or a stub).
    ///   - now: Injected clock for the relative date windows and the `from=today`
    ///     request bound. Defaults to the system clock; tests pass a fixed date.
    public init(
        fetcher: any ConcertsFetching,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fetcher = fetcher
        self.now = now
    }

    /// The window narrowed by the current ``filter``, evaluated against `now`.
    public var filtered: [Concert] {
        let reference = now()
        return allConcerts.filter { filter.matches($0, now: reference) }
    }

    /// The distinct venues present in the fetched window, grouped by region for
    /// the filter sheet's venue checklist.
    public var venueGroups: [VenueRegionGroup] {
        VenueGrouping.groupedByRegion(allConcerts.map(\.venue))
    }

    /// Fetches the whole curated window, exhausting pagination. Safe to call again
    /// for pull-to-refresh / foreground refresh: an already-populated list keeps
    /// showing while the refetch runs, and a failed refetch that still has cached
    /// rows stays in ``Phase/loaded`` rather than flashing an error.
    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        if allConcerts.isEmpty {
            phase = .loading
        }
        do {
            allConcerts = try await fetchAllPages()
            phase = .loaded
        } catch is CancellationError {
            return
        } catch {
            Log(.error, category: .network, "OnTourModel.load failed: \(error)")
            if allConcerts.isEmpty {
                phase = .failed
            }
        }
    }

    /// Requests `curated` pages from `today` forward, appending until the server
    /// reports no more pages or the ``pageCap`` is reached.
    private func fetchAllPages() async throws -> [Concert] {
        let today = now()
        var collected: [Concert] = []
        var page = 1
        while page <= Self.pageCap {
            let response = try await fetcher.fetchConcerts(
                curated: true,
                from: today,
                to: nil,
                page: page,
                limit: Self.pageSize
            )
            collected.append(contentsOf: response.concerts)
            guard Self.hasMorePages(response.pagination, lastPageCount: response.concerts.count) else {
                return collected
            }
            page += 1
        }
        Log(.warning, category: .network,
            "OnTourModel: hit \(Self.pageCap)-page cap; concert list may be truncated")
        return collected
    }

    /// Whether another page follows. Prefers the server's `hasMore`; when the
    /// server omits it, a full page (`count == limit`) implies there may be more.
    static func hasMorePages(_ pagination: PaginationInfo, lastPageCount: Int) -> Bool {
        if let hasMore = pagination.hasMore {
            return hasMore
        }
        return lastPageCount == pagination.limit
    }
}
