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
        "An observer subscribing immediately after construction receives the cached playlist, not .empty",
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

        // A fetcher whose result is distinguishable from the cached playlist,
        // so the assertion below can tell "got the cache" from "got a fetch".
        let mockFetcher = MockPlaylistFetcher()
        mockFetcher.playlistToReturn = .stub(playcuts: [
            .stub(songTitle: "Back, Baby", labelName: "Drag City", artistName: "Jessica Pratt", releaseTitle: "On Your Own Love Again")
        ])

        let service = PlaylistService(
            fetcher: mockFetcher,
            interval: 30,
            cacheCoordinator: cacheCoordinator,
            apiVersion: .v1
        )

        // When - subscribe immediately, with no explicit wait for the cache
        // load in between.
        var iterator = service.updates().makeAsyncIterator()
        let firstPlaylist = await iterator.next()

        // Then - the first value observed is the cached playlist, never the
        // `.empty` pre-load sentinel and never the freshly-fetched one.
        let unwrapped = try #require(firstPlaylist)
        #expect(unwrapped != .empty)
        #expect(unwrapped.playcuts.first?.songTitle == "la paradoja")
    }
}
