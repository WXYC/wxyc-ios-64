//
//  PlaylistServiceFetchErrorCountTests.swift
//  Playlist
//
//  Tests for PlaylistService's fetch-error observability counter
//  (WXYC/wxyc-ios-64#267). Fetch failures are swallowed to an empty playlist
//  by design — `PlaylistFetcher.fetchPlaylist()` never throws — and the
//  broadcast-empty guard in `ingest(_:)` intentionally keeps the last good
//  playlist on screen through a transient failure (don't clear good data on
//  a single hiccup). That guard is correct and untouched here; what was
//  missing is any signal that a failure happened at all, which left a
//  sustained failure (decoder drift, a bad deploy) indistinguishable from a
//  quiet night with nothing playing.
//
//  Created by Jake Bromberg on 08/10/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import LoggerTesting
import AnalyticsTesting
import PlaylistTesting
@testable import Playlist
@testable import Caching

@Suite("PlaylistService Fetch Error Count Tests")
struct PlaylistServiceFetchErrorCountTests {
    @Test("fetchErrorCount is zero before any fetch")
    func fetchErrorCountStartsAtZero() async {
        let dataSource = MockPlaylistDataSource()
        let fetcher = PlaylistFetcher(
            dataSource: dataSource,
            errorReporter: MockErrorReporter(),
            analytics: MockStructuredAnalytics()
        )
        let service = PlaylistService(
            fetcher: fetcher,
            interval: 30,
            cacheCoordinator: CacheCoordinator(cache: InMemoryCache()),
            apiVersion: .v1
        )

        #expect(await service.fetchErrorCount() == 0)
    }

    @Test("a transient fetch failure increments fetchErrorCount and preserves the prior playlist, then a subsequent success recovers")
    func transientFailureIncrementsCountAndRecoversOnSuccess() async {
        let dataSource = MockPlaylistDataSource()
        let fetcher = PlaylistFetcher(
            dataSource: dataSource,
            errorReporter: MockErrorReporter(),
            analytics: MockStructuredAnalytics()
        )
        let service = PlaylistService(
            fetcher: fetcher,
            interval: 30,
            cacheCoordinator: CacheCoordinator(cache: InMemoryCache()),
            apiVersion: .v1
        )

        // Seed good data via a first successful fetch.
        let goodPlaylist = Playlist.stub(playcuts: [
            .stub(songTitle: "la paradoja", artistName: "Juana Molina")
        ])
        dataSource.playlistToReturn = goodPlaylist
        _ = await service.fetchAndCachePlaylist()
        #expect(await service.currentPlaylistSnapshot() == goodPlaylist)
        #expect(await service.fetchErrorCount() == 0)

        // A transient failure: the fetch throws, the fetcher swallows it to
        // `.empty`, and the broadcast-empty guard keeps the prior good data on
        // screen — that part is unchanged. What must be true now is that the
        // failure is *observable*.
        dataSource.errorToThrow = URLError(.timedOut)
        let duringFailure = await service.fetchAndCachePlaylist()
        #expect(duringFailure == .empty)
        #expect(await service.currentPlaylistSnapshot() == goodPlaylist, "the prior playlist must survive a transient failure")
        #expect(await service.fetchErrorCount() == 1)

        // Recovery: the next fetch succeeds again and fresh data replaces the
        // stale snapshot. The error count must not move on a success.
        dataSource.errorToThrow = nil
        let recoveredPlaylist = Playlist.stub(playcuts: [
            .stub(id: 2, hour: 2000, songTitle: "Back, Baby", artistName: "Jessica Pratt")
        ])
        dataSource.playlistToReturn = recoveredPlaylist
        _ = await service.fetchAndCachePlaylist()
        #expect(await service.currentPlaylistSnapshot() == recoveredPlaylist)
        #expect(await service.fetchErrorCount() == 1)
    }

    @Test("sustained failures keep accumulating fetchErrorCount across repeated polls")
    func sustainedFailuresAccumulate() async {
        let dataSource = MockPlaylistDataSource()
        dataSource.errorToThrow = URLError(.cannotConnectToHost)
        let fetcher = PlaylistFetcher(
            dataSource: dataSource,
            errorReporter: MockErrorReporter(),
            analytics: MockStructuredAnalytics()
        )
        let service = PlaylistService(
            fetcher: fetcher,
            interval: 30,
            cacheCoordinator: CacheCoordinator(cache: InMemoryCache()),
            apiVersion: .v1
        )

        for expectedCount in 1...3 {
            _ = await service.fetchAndCachePlaylist()
            #expect(await service.fetchErrorCount() == expectedCount)
        }
    }
}
