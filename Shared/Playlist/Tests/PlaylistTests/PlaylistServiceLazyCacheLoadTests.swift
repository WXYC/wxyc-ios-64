//
//  PlaylistServiceLazyCacheLoadTests.swift
//  Playlist
//
//  Guards WXYC/wxyc-ios-64#964: constructing a PlaylistService must not read
//  the disk cache. The cache load starts on first use — waitForCacheLoad()
//  or an updates() subscription — not in init, so the PlaylistServiceEnvironment
//  fallback (built on every correctly-injecting launch, see
//  PlaylistServiceEnvironment.swift) costs an allocation and nothing else.
//
//  Created by Jake Bromberg on 08/18/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import PlaylistTesting
@testable import Playlist
@testable import Caching

/// A ``Cache`` that counts reads (``metadataResult(for:)`` / ``data(for:)``)
/// separately from writes, so a test can assert "no read happened" without
/// caring how many times a value was written.
///
/// Wraps an ``InMemoryCache`` rather than reimplementing storage — this
/// double only needs to observe traffic, not model it.
private final class CountingCache: Cache, @unchecked Sendable {
    private let wrapped = InMemoryCache()
    private let lock = NSLock()
    private var _readCount = 0

    var readCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _readCount
    }

    private func recordRead() {
        lock.lock()
        _readCount += 1
        lock.unlock()
    }

    func metadata(for key: String) -> CacheMetadata? {
        recordRead()
        return wrapped.metadata(for: key)
    }

    func metadataResult(for key: String) -> MetadataReadResult {
        recordRead()
        return wrapped.metadataResult(for: key)
    }

    func data(for key: String) -> Data? {
        recordRead()
        return wrapped.data(for: key)
    }

    func set(_ data: Data?, metadata: CacheMetadata, for key: String) {
        wrapped.set(data, metadata: metadata, for: key)
    }

    func remove(for key: String) {
        wrapped.remove(for: key)
    }

    func allMetadata() -> [(key: String, metadata: CacheMetadata)] {
        wrapped.allMetadata()
    }

    func clearAll() {
        wrapped.clearAll()
    }

    func totalSize() -> Int64 {
        wrapped.totalSize()
    }
}

/// Accumulates the playlists delivered to a subscription, so a test can assert
/// on how many arrived rather than only on the first.
private actor Collector {
    private(set) var values: [Playlist] = []

    func append(_ playlist: Playlist) {
        values.append(playlist)
    }
}

@Suite("PlaylistService Lazy Cache Load Tests")
struct PlaylistServiceLazyCacheLoadTests {

    @Test("Constructing a PlaylistService performs no cache read", .timeLimit(.minutes(1)))
    func constructionPerformsNoCacheRead() async throws {
        // Given - a cache double that counts reads, and a service built
        // against it.
        let countingCache = CountingCache()
        let cacheCoordinator = CacheCoordinator(cache: countingCache)

        let service = PlaylistService(
            fetcher: MockPlaylistFetcher(),
            interval: 30,
            cacheCoordinator: cacheCoordinator,
            apiVersion: .v1
        )

        // When - give any eagerly-started background work a chance to run.
        // An `init` that starts a cache-load Task would have completed it
        // well within this window; a lazy `init` never schedules one at all.
        try await Task.sleep(for: .milliseconds(100))

        // Then - construction alone must not have touched the cache.
        #expect(countingCache.readCount == 0)

        // And - the first actual use starts (and completes) the load.
        await service.waitForCacheLoad()
        #expect(countingCache.readCount > 0)
    }

    @Test(
        "An observer subscribing immediately after construction receives the cached playlist without waiting for a fetch",
        .timeLimit(.minutes(1))
    )
    func observerImmediatelyAfterConstructionSeesCachedPlaylist() async throws {
        // Given - a cache pre-seeded with a real playlist, as if a previous
        // launch had written it.
        let cacheCoordinator = CacheCoordinator(cache: InMemoryCache())
        let cachedPlaylist = Playlist.stub(playcuts: [
            .stub(songTitle: "la paradoja", labelName: "Sonamos", artistName: "Juana Molina", releaseTitle: "DOGA")
        ])
        await cacheCoordinator.set(
            value: cachedPlaylist,
            for: PlaylistCacheKey.playlist(for: .v1),
            lifespan: 15 * 60
        )

        // A fetcher parked at a gate this test never releases, standing in for
        // a network fetch still in flight.
        //
        // The park is what keeps this test from going vacuous. Asserting only
        // that the first value is the cached one passes even with the barrier
        // below removed, because `ingest(_:)` awaits the cache load itself and
        // broadcasts the cached playlist ahead of the fetched one — the right
        // answer arriving for the wrong reason. Parking the fetch removes that
        // second source entirely: the only thing that can deliver a value here
        // is `addContinuation(_:for:)`'s own barrier, so a regression surfaces
        // as no value at all rather than as the wrong one.
        let fetcher = GatedPlaylistFetcher(playlist: .stub(playcuts: [
            .stub(songTitle: "Back, Baby", labelName: "Drag City", artistName: "Jessica Pratt", releaseTitle: "On Your Own Love Again")
        ]))

        let service = PlaylistService(
            fetcher: fetcher,
            interval: 30,
            cacheCoordinator: cacheCoordinator,
            apiVersion: .v1
        )

        // When - subscribe immediately, with no explicit wait for the cache
        // load in between.
        let subscription = Task { () -> Playlist? in
            var iterator = service.updates().makeAsyncIterator()
            return await iterator.next()
        }

        // Bound the wait so a regression fails in seconds instead of hanging
        // until the suite's time limit. This bounds the *failure* path only:
        // on the success path the barrier yields within a couple of actor
        // hops. The margin is deliberately wide — this suite is neither
        // `.serialized` nor `@MainActor` and runs alongside the rest of the
        // package, so a bound close to the real success path would turn
        // scheduling contention into a flake. Cancelling the subscription ends
        // its `AsyncStream` iteration, so `next()` resolves to `nil`.
        let deadline = Task {
            try? await Task.sleep(for: .seconds(5))
            subscription.cancel()
        }
        let firstPlaylist = await subscription.value
        deadline.cancel()
        fetcher.release()

        // Then - the first value observed is the cached playlist, delivered
        // ahead of any fetch and never the `.empty` pre-load sentinel.
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
        // Given - a pre-seeded cache and a fetcher parked at a gate, so the
        // only values that can reach a subscriber come from the cache load.
        let cacheCoordinator = CacheCoordinator(cache: InMemoryCache())
        await cacheCoordinator.set(
            value: Playlist.stub(playcuts: [
                .stub(songTitle: "la paradoja", labelName: "Sonamos", artistName: "Juana Molina", releaseTitle: "DOGA")
            ]),
            for: PlaylistCacheKey.playlist(for: .v1),
            lifespan: 15 * 60
        )

        let fetcher = GatedPlaylistFetcher(playlist: .empty)
        let service = PlaylistService(
            fetcher: fetcher,
            interval: 30,
            cacheCoordinator: cacheCoordinator,
            apiVersion: .v1
        )

        // When - the very first subscriber attaches, which is the launch path:
        // deferring the load guarantees this subscription lands before the
        // load rather than after it.
        let collected = Collector()
        let subscription = Task {
            for await playlist in service.updates() {
                await collected.append(playlist)
            }
        }
        try await Task.sleep(for: .milliseconds(300))
        subscription.cancel()
        fetcher.release()

        // Then - exactly one delivery. `loadCachedPlaylist()` broadcasts to
        // every registered continuation, so registering this one before
        // awaiting the load makes the subscriber receive the cached playlist
        // from that broadcast *and* again from the explicit post-barrier
        // yield. Nothing is corrupted by the duplicate, but every downstream
        // observer pays for it: `WidgetStateService` spends a reload against
        // the widget refresh budget and `NowPlayingService` re-fetches artwork
        // and re-emits a now-playing item.
        let values = await collected.values
        #expect(values.count == 1)
        #expect(values.first?.playcuts.first?.songTitle == "la paradoja")
    }

    @Test(
        "switchAPIVersion on a service nothing subscribed to still clears the playlist",
        .timeLimit(.minutes(1))
    )
    func switchAPIVersionClearsPlaylistWithoutPriorSubscription() async throws {
        // Given - a cache holding content under the version being switched *to*,
        // and a service on .v1 that nothing has ever subscribed to, so the
        // initial cache load has not run.
        let cacheCoordinator = CacheCoordinator(cache: InMemoryCache())
        await cacheCoordinator.set(
            value: Playlist.stub(playcuts: [
                .stub(songTitle: "la paradoja", labelName: "Sonamos", artistName: "Juana Molina", releaseTitle: "DOGA")
            ]),
            for: PlaylistCacheKey.playlist(for: .v2),
            lifespan: 15 * 60
        )

        // A fetcher that fails, so the post-switch fetch cannot supply content
        // and the only thing that could repopulate the playlist is a cache load.
        let mockFetcher = MockPlaylistFetcher()
        mockFetcher.playlistToReturn = .empty

        let service = PlaylistService(
            fetcher: mockFetcher,
            interval: 30,
            cacheCoordinator: cacheCoordinator,
            apiVersion: .v1
        )

        // When - switching versions, which clears the playlist to show a
        // loading state and then fetches fresh data.
        await service.switchAPIVersion(to: .v2)

        // Then - the clear stands. `switchAPIVersion` documents that it clears
        // the playlist "to ensure clean data"; that has to hold whether or not
        // anything happened to subscribe first, rather than depending on a
        // prior subscription having settled the cache load.
        let snapshot = await service.currentPlaylistSnapshot()
        #expect(snapshot.isContentEmpty)
    }

    @Test(
        "A failing fetch on an unsubscribed service does not clobber the cached playlist",
        .timeLimit(.minutes(1))
    )
    func failedFetchWithoutSubscriptionPreservesCachedPlaylist() async throws {
        // Given - a disk cache holding a good playlist from a previous
        // session, exactly as the widget would read it.
        let cacheCoordinator = CacheCoordinator(cache: InMemoryCache())
        let cachedPlaylist = Playlist.stub(playcuts: [
            .stub(songTitle: "la paradoja", labelName: "Sonamos", artistName: "Juana Molina", releaseTitle: "DOGA")
        ])
        await cacheCoordinator.set(
            value: cachedPlaylist,
            for: PlaylistCacheKey.playlist(for: .v1),
            lifespan: 15 * 60
        )

        // And - a fetcher that fails, parked inside `fetchPlaylist()`.
        // `PlaylistFetcherProtocol` swallows every error into `.empty`, so an
        // empty return is what a network timeout looks like from the service's
        // side. The park is what makes this test *discriminating*: a real
        // network fetch takes far longer than a disk read, so any
        // eagerly-started cache load would have long since finished by the time
        // the fetch resolves. An instant mock fetcher would instead beat the
        // disk read and fail this test on any implementation, proving nothing.
        let fetcher = GatedPlaylistFetcher(playlist: .empty)

        let service = PlaylistService(
            fetcher: fetcher,
            interval: 30,
            cacheCoordinator: cacheCoordinator,
            apiVersion: .v1
        )

        // When - a background-launched refresh fetches with nothing having
        // subscribed and nothing having awaited the cache-load barrier. This
        // is `BackgroundRefreshController.handleRefresh` in a process with no
        // views: `.backgroundTask(.appRefresh(_:))` fires, so no `updates()`
        // subscription and no `waitForCacheLoad()` ever precedes the fetch.
        let refresh = Task { await service.fetchAndCachePlaylist() }

        // Hold the fetch at the gate long enough that a cache load running
        // concurrently would certainly have completed, then let it return.
        await fetcher.waitForEntry()
        try await Task.sleep(for: .milliseconds(100))
        fetcher.release()
        _ = await refresh.value

        // Then - the good playlist is still on disk. `ingest(_:)`'s
        // broadcast-empty guard must have rejected the empty fetch, which
        // requires it to have compared against the *cached* playlist rather
        // than an unloaded `.empty` in-memory state.
        let surviving: Playlist = try await cacheCoordinator.value(
            for: PlaylistCacheKey.playlist(for: .v1)
        )
        #expect(surviving.playcuts.first?.songTitle == "la paradoja")
    }
}
