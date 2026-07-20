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

    /// Single-flight coalescing: the in-flight load's task, if any. A concurrent
    /// ``load()`` awaits this same task instead of kicking off a second pagination
    /// sweep, so an error-state retry that overlaps a tab-reappearance `.task` (or
    /// a foreground refresh racing the initial load) doesn't double-fetch — and,
    /// crucially, the deep-link ``resolveConcert(id:)`` awaits the in-flight load
    /// rather than racing past a not-yet-populated window into a by-id fetch.
    /// Cleared when the sweep finishes so the next ``load()`` (pull-to-refresh)
    /// starts fresh. Main-actor isolation makes the check-and-set atomic.
    private var loadTask: Task<Void, Never>?

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

    /// The distinct Discogs genres present in the fetched window, de-duplicated
    /// and sorted — the chip vocabulary for the filter sheet's genre section.
    /// Empty when no show in the window carries a genre, in which case the sheet
    /// omits the genre section entirely (the vocabulary is always derived from
    /// the data, never a hardcoded taxonomy list).
    public var availableGenres: [String] {
        Set(allConcerts.flatMap { $0.genres ?? [] }).sorted()
    }

    /// Fetches the whole curated window, exhausting pagination. Safe to call again
    /// for pull-to-refresh / foreground refresh: an already-populated list keeps
    /// showing while the refetch runs, and a failed refetch that still has cached
    /// rows stays in ``Phase/loaded`` rather than flashing an error.
    public func load() async {
        if let loadTask {
            // A load is already in flight — await it instead of starting a second
            // sweep. The concurrent caller then observes the loaded window.
            await loadTask.value
            return
        }
        let task = Task {
            await self.performLoad()
            self.loadTask = nil
        }
        loadTask = task
        await task.value
    }

    /// The actual pagination sweep, run by exactly one ``load()`` at a time.
    private func performLoad() async {
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

    /// Resolves a shared deep link's concert id to a ``ConcertResolution``,
    /// running the three-rung ladder (#537):
    ///
    /// 1. **window** — if the id is in the loaded window, return it for a
    ///    zoom-from-row presentation. Loads the window first if it isn't loaded
    ///    yet (a cold launch straight into a share link), so the common
    ///    in-window case doesn't have to round-trip a by-id fetch.
    /// 2. **byID** — otherwise fetch the single concert directly, covering shows
    ///    beyond the loaded page range.
    /// 3. **missed** — if the by-id fetch also fails (unknown id, or the endpoint
    ///    isn't available), give up so the tab can show a "couldn't find that
    ///    show" notice.
    ///
    /// - Parameter id: The concert id from `wxyc.org/shows/<id>` (or `wxyc://concert/<id>`).
    /// - Returns: How the link resolved.
    public func resolveConcert(id: Int) async -> ConcertResolution {
        if phase != .loaded {
            await load()
        }
        if let hit = allConcerts.first(where: { $0.id == id }) {
            return .window(hit)
        }
        if let fetched = try? await fetcher.fetchConcert(id: id) {
            return .byID(fetched)
        }
        return .missed
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
