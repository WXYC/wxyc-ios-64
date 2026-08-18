//
//  PlaylistServiceLazyCacheLoadTests.swift
//  Playlist
//
//  Guards WXYC/wxyc-ios-64#964: constructing a PlaylistService must start no
//  work. The cache load begins on first use — waitForCacheLoad() or an
//  updates() subscription — not in init, so the PlaylistServiceEnvironment
//  fallback (built on every correctly-injecting launch, see
//  PlaylistServiceEnvironment.swift) sits inert instead of reading the disk
//  cache. Also covers what deferring the load put at risk: the ordering
//  guarantee a subscriber depends on, and the empty-fetch guard in ingest(_:).
//
//  Created by Jake Bromberg on 08/18/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import Synchronization
import CachingTesting
import CoreTesting
import PlaylistTesting
@testable import Playlist
@testable import Caching

@Suite("PlaylistService Lazy Cache Load Tests")
struct PlaylistServiceLazyCacheLoadTests {

    /// A previous session's playlist, as the app group's cache would hold it.
    private static let cachedPlaylist = Playlist.stub(playcuts: [.stub()])

    /// A cache coordinator pre-seeded with ``cachedPlaylist`` under `version`'s key.
    ///
    /// - Parameter agedOut: When `true`, the entry is aged past the 15-minute
    ///   `PlaylistService.cacheLifespan` it was written with. That is the *normal*
    ///   state on the background-refresh path — BGAppRefresh fires far less often than
    ///   every 15 minutes — so a test that only ever seeds a live entry exercises the
    ///   rarer of the two.
    private func seededCoordinator(
        version: PlaylistAPIVersion = .v1,
        cache: Cache = InMemoryCache(),
        agedOut: Bool = false
    ) async -> CacheCoordinator {
        let clock = MockClock()
        let coordinator = CacheCoordinator(cache: cache, clock: clock)
        await coordinator.set(
            value: Self.cachedPlaylist,
            for: PlaylistCacheKey.playlist(for: version),
            lifespan: 15 * 60
        )
        if agedOut {
            clock.advance(by: 16 * 60)
        }
        return coordinator
    }

    @Test("Constructing a PlaylistService starts no cache load", .timeLimit(.minutes(1)))
    func constructionStartsNoCacheLoad() async throws {
        // Given - a cache double that counts reads, and a service built against it.
        let countingCache = CountingCache()
        let service = PlaylistService(
            fetcher: MockPlaylistFetcher(),
            interval: 30,
            cacheCoordinator: CacheCoordinator(cache: countingCache),
            apiVersion: .v1
        )

        // Then - construction started nothing. Asserted on the wiring rather than by
        // sleeping and re-checking a counter: the baseline is assigned synchronously,
        // before any task body runs, so this needs no timing tolerance. A sleep long
        // enough for "an eager load would have finished by now" passes on a loaded
        // machine whether or not the regression is present.
        #expect(await service.wiringSnapshot().cacheLoadStarted == false)
        #expect(countingCache.getCallCount == 0)

        // And - the first actual use starts the load, and reads the cache.
        await service.waitForCacheLoad()
        #expect(await service.wiringSnapshot().cacheLoadStarted)
        #expect(countingCache.getCallCount > 0)
    }

    @Test(
        "An observer subscribing immediately after construction receives the cached playlist without waiting for a fetch",
        .timeLimit(.minutes(1))
    )
    func observerImmediatelyAfterConstructionSeesCachedPlaylist() async throws {
        // Given - a cache pre-seeded as if a previous launch had written it, and a
        // fetcher parked at a gate this test never releases, standing in for a network
        // fetch still in flight.
        //
        // The park is what keeps this test from going vacuous. Asserting only that the
        // first value is the cached one passes even with the barrier in
        // `addContinuation(_:for:)` removed, because `ingest(_:)` awaits the cache load
        // itself and broadcasts the cached playlist ahead of the fetched one — the right
        // answer arriving for the wrong reason. Parking the fetch removes that second
        // source entirely: the only thing that can deliver a value here is the barrier
        // under test, so a regression surfaces as no value at all rather than the wrong
        // one.
        let fetcher = GatedPlaylistFetcher(playlist: .stub(playcuts: [
            .stub(songTitle: "Back, Baby", artistName: "Jessica Pratt", releaseTitle: "On Your Own Love Again")
        ]))
        let service = PlaylistService(
            fetcher: fetcher,
            interval: 30,
            cacheCoordinator: await seededCoordinator(),
            apiVersion: .v1
        )

        // When - subscribe immediately, with no explicit wait for the cache load between.
        let subscription = Task { () -> Playlist? in
            var iterator = service.updates().makeAsyncIterator()
            return await iterator.next()
        }

        // Bound the wait so a regression fails in seconds instead of hanging until the
        // suite's time limit. This bounds the *failure* path only: on the success path
        // the barrier yields within a couple of actor hops. The margin is deliberately
        // wide — this suite is neither `.serialized` nor `@MainActor` and runs alongside
        // the rest of the package, so a bound close to the real success path would turn
        // scheduling contention into a flake. Cancelling the subscription ends its
        // `AsyncStream` iteration, so `next()` resolves to `nil`.
        let deadline = Task {
            try? await Task.sleep(for: .seconds(5))
            subscription.cancel()
        }
        let firstPlaylist = await subscription.value
        deadline.cancel()
        fetcher.release()

        // Then - the first value observed is the cached playlist, delivered ahead of any
        // fetch and never the `.empty` pre-load sentinel.
        let unwrapped = try #require(
            firstPlaylist,
            "Subscriber received no playlist while the fetch was parked: addContinuation(_:for:) did not await the cache load before deciding whether to yield."
        )
        #expect(unwrapped != .empty)
        #expect(unwrapped.playcuts.first?.songTitle == "la paradoja")
    }

    @Test(
        "The first subscriber receives the cached playlist once, not twice",
        .timeLimit(.minutes(1))
    )
    func firstSubscriberReceivesCachedPlaylistExactlyOnce() async throws {
        // Given - a pre-seeded cache and a fetcher parked at a gate, so the only values
        // that can reach a subscriber come from the cache load.
        let fetcher = GatedPlaylistFetcher(playlist: .empty)
        let service = PlaylistService(
            fetcher: fetcher,
            interval: 30,
            cacheCoordinator: await seededCoordinator(),
            apiVersion: .v1
        )

        // When - the very first subscriber attaches, which is the launch path: deferring
        // the load guarantees this subscription lands before the load rather than after.
        let subscription = Task { () -> [Playlist] in
            var values: [Playlist] = []
            for await playlist in service.updates() {
                values.append(playlist)
            }
            return values
        }

        // Wait for the first delivery, then settle briefly. A duplicate is yielded on the
        // same actor turn as the value it duplicates, so this window only has to outlast
        // one hop — the `waitUntil` above it is what absorbs scheduling contention.
        #expect(await waitUntil { await service.currentPlaylistSnapshot().isContentEmpty == false })
        try await Task.sleep(for: .milliseconds(50))
        subscription.cancel()
        fetcher.release()

        // Then - exactly one delivery. The duplicate costs a `WidgetStateService` reload
        // against the widget refresh budget and a `NowPlayingService` artwork re-fetch;
        // see `addContinuation(_:for:)` for why registering before the barrier makes the
        // load's broadcast and the explicit yield both fire.
        let values = await subscription.value
        #expect(values.count == 1)
        #expect(values.first?.playcuts.first?.songTitle == "la paradoja")
    }

    @Test(
        "switchAPIVersion on a service nothing subscribed to still clears the playlist",
        .timeLimit(.minutes(1))
    )
    func switchAPIVersionClearsPlaylistWithoutPriorSubscription() async throws {
        // Given - a cache holding content under the version being switched *to*, and a
        // service on .v1 that nothing has ever subscribed to, so no load has run.
        //
        // The fetcher fails, so the post-switch fetch cannot supply content and a cache
        // load is the only thing that could repopulate the playlist.
        let mockFetcher = MockPlaylistFetcher()
        mockFetcher.playlistToReturn = .empty

        let service = PlaylistService(
            fetcher: mockFetcher,
            interval: 30,
            cacheCoordinator: await seededCoordinator(version: .v2),
            apiVersion: .v1
        )

        // When - switching versions, which clears the playlist to show a loading state
        // and then fetches fresh data.
        await service.switchAPIVersion(to: .v2)

        // Then - the clear stands. `switchAPIVersion` documents that it clears the
        // playlist "to ensure clean data"; that has to hold whether or not anything
        // happened to subscribe first, rather than depending on a prior subscription
        // having settled the cache baseline.
        #expect(await service.currentPlaylistSnapshot().isContentEmpty)
    }

    @Test(
        "A failing fetch on an unsubscribed service does not clobber the cached playlist",
        .timeLimit(.minutes(1))
    )
    func failedFetchWithoutSubscriptionPreservesCachedPlaylist() async throws {
        // Given - a disk cache holding a good playlist from a previous session, exactly
        // as the widget would read it.
        let cacheCoordinator = await seededCoordinator()

        // And - a fetcher that fails and returns *instantly*.
        // `PlaylistFetcherProtocol` swallows every error into `.empty`, so an empty
        // return is what a network timeout looks like from the service's side.
        //
        // Returning instantly is the load-bearing detail. `fetchAndCachePlaylist()` kicks
        // the cache load before fetching, so a slow fetch lets the disk read finish first
        // and `ingest(_:)` compares against a populated playlist no matter what. An
        // instant fetch wins that race, which is exactly the condition `ingest`'s barrier
        // exists to survive: without it the guard reads an unloaded `.empty`
        // `currentPlaylist`, mistakes a failed fetch for the first real data, and writes
        // the empty playlist over the app group's cache.
        let mockFetcher = MockPlaylistFetcher()
        mockFetcher.playlistToReturn = .empty

        let service = PlaylistService(
            fetcher: mockFetcher,
            interval: 30,
            cacheCoordinator: cacheCoordinator,
            apiVersion: .v1
        )

        // When - a background-launched refresh fetches with nothing having subscribed and
        // nothing having awaited the cache-load barrier. This is
        // `BackgroundRefreshController.handleRefresh` in a process with no views:
        // `.backgroundTask(.appRefresh(_:))` fires, so no `updates()` subscription and no
        // `waitForCacheLoad()` ever precedes the fetch.
        _ = await service.fetchAndCachePlaylist()

        // Then - the good playlist is still on disk.
        let surviving: Playlist = try await cacheCoordinator.value(
            for: PlaylistCacheKey.playlist(for: .v1)
        )
        #expect(surviving.playcuts.first?.songTitle == "la paradoja")
    }

    @Test(
        "A failing fetch on an unsubscribed service does not cache an empty playlist over an expired entry",
        .timeLimit(.minutes(1))
    )
    func failedFetchWithExpiredCacheDoesNotCacheEmptyPlaylist() async throws {
        // Given - the same background-refresh setup as the test above, except that the
        // cached entry has aged out. This is the state that path is normally in:
        // `cacheLifespan` is 15 minutes and BGAppRefresh fires far less often, so the
        // sibling test's live entry is the exception rather than the rule.
        //
        // What that changes is where `currentPlaylist` ends up. `loadCachedPlaylist()`
        // catches the throw from an expired read, logs, and leaves `currentPlaylist` at
        // `.empty` while still settling the baseline — so `ingest(_:)`'s barrier is
        // satisfied and its guard sees an empty playlist either way. The barrier alone
        // therefore protects nothing here.
        let cacheCoordinator = await seededCoordinator(agedOut: true)

        let mockFetcher = MockPlaylistFetcher()
        mockFetcher.playlistToReturn = .empty

        let service = PlaylistService(
            fetcher: mockFetcher,
            interval: 30,
            cacheCoordinator: cacheCoordinator,
            apiVersion: .v1
        )

        // When - the background refresh runs with nothing subscribed.
        _ = await service.fetchAndCachePlaylist()

        // Then - nothing sits under the key. The expired entry is already gone by now —
        // `CacheCoordinator.value(for:)` removes an entry it finds expired — so what has
        // to hold is that the failed fetch did not put a *fresh* empty one in its place.
        // A miss is what sends `fetchPlaylist()`, the widget's read, to the network; a
        // fresh empty entry is served to it as a hit for the full 15 minutes.
        let entries = await cacheCoordinator.allEntries()
        #expect(
            entries.isEmpty,
            "A failed fetch cached an empty playlist, which the widget will be served as a hit for 15 minutes: \(entries.map(\.key))"
        )
    }

    @Test(
        "switchAPIVersion cancels a cache load in flight rather than letting it publish the old version's rows",
        .timeLimit(.minutes(1))
    )
    func switchAPIVersionCancelsInFlightCacheLoad() async throws {
        // Given - a v1 cache whose first read parks, so the load can be held at
        // `CacheBaseline.loading` for the whole of the switch.
        let cache = GatedReadCache()
        let cacheCoordinator = await seededCoordinator(version: .v1, cache: cache)

        let mockFetcher = MockPlaylistFetcher()
        mockFetcher.playlistToReturn = .empty

        let service = PlaylistService(
            fetcher: mockFetcher,
            interval: 30,
            cacheCoordinator: cacheCoordinator,
            apiVersion: .v1
        )

        // And - a load actually in flight. Asserting it is parked, rather than starting it
        // and hoping, is what stops this test going vacuous: an unparked load against an
        // in-memory cache settles the baseline before the switch runs, and there would be
        // nothing left for the switch to orphan.
        let load = Task { await service.waitForCacheLoad() }
        #expect(await waitUntil(timeout: .seconds(5)) { cache.isParked })

        // When - the version switches while that load is parked, and the read is released
        // only afterwards. `apiVersion` is reassigned in the same synchronous actor turn
        // that settles the baseline, so observing it pins the release to a point after the
        // switch has asserted its clear — without assuming anything about whether the
        // switch's own fetch reached the cache first.
        let switchTask = Task { await service.switchAPIVersion(to: .v2) }
        #expect(await waitUntil(timeout: .seconds(5)) { await service.wiringSnapshot().apiVersion == .v2 })
        cache.open()
        await switchTask.value
        await load.value

        // Then - the clear stands. `loadCachedPlaylist()` evaluates `cacheKey` before its
        // suspension, so the orphaned load comes back holding v1's rows; publishing them
        // would undo the switch's deliberate clear and put two incompatible `chronOrderID`
        // scales on screen at once.
        #expect(
            await service.currentPlaylistSnapshot().isContentEmpty,
            "A cache load orphaned by switchAPIVersion published the pre-switch version's rows over the clear."
        )
    }
}

/// A ``Cache`` decorator that parks its first metadata read until the test opens the
/// gate, so a test can hold `PlaylistService`'s cache load at `CacheBaseline.loading`
/// and drive a version switch at it.
///
/// The park is a blocking semaphore wait rather than an async suspension, unlike
/// `GatedPlaylistFetcher`: `Cache` is a synchronous protocol, so the read runs to
/// completion inside `CacheCoordinator`'s actor with no suspension point to hold. It
/// occupies one cooperative thread until ``open()`` and carries its own timeout, so a
/// test that never opens the gate fails on an assertion rather than wedging the run.
///
/// Only the first read parks. Seeding writes through `set(_:metadata:for:)` and the
/// coordinator's init purge reads `allMetadata()`, so neither trips the gate.
private final class GatedReadCache: Cache, @unchecked Sendable {
    private struct State {
        var isParked = false
        var isOpen = false
    }

    private let inner = InMemoryCache()
    private let gate = DispatchSemaphore(value: 0)
    private let state = Mutex(State())

    /// True while a read is parked at the gate.
    var isParked: Bool { state.withLock { $0.isParked } }

    /// Releases the parked read and lets every later read through.
    func open() {
        state.withLock { $0.isOpen = true }
        gate.signal()
    }

    func metadata(for key: String) -> CacheMetadata? {
        let shouldPark = state.withLock { state -> Bool in
            guard !state.isOpen, !state.isParked else { return false }
            state.isParked = true
            return true
        }
        if shouldPark {
            _ = gate.wait(timeout: .now() + 30)
            state.withLock { $0.isParked = false }
        }
        return inner.metadata(for: key)
    }

    func data(for key: String) -> Data? {
        inner.data(for: key)
    }

    func set(_ data: Data?, metadata: CacheMetadata, for key: String) {
        inner.set(data, metadata: metadata, for: key)
    }

    func remove(for key: String) {
        inner.remove(for: key)
    }

    func allMetadata() -> [(key: String, metadata: CacheMetadata)] {
        inner.allMetadata()
    }

    func clearAll() {
        inner.clearAll()
    }

    func totalSize() -> Int64 {
        inner.totalSize()
    }
}
