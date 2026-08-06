//
//  PlaylistServiceLiveUpdatesTests.swift
//  Playlist
//
//  Verifies PlaylistService's live-fs SSE integration (#269): insert appends,
//  update replaces the row by id, an out-of-order update appends, a duplicate
//  insert is idempotent, refetch triggers a reconciliation fetch, events are
//  gated on the foreground state, and backgrounding tears the subscription down
//  so a later foreground reconnects. See WXYC/wxyc-ios-64#269.
//
//  Every test below that injects a `liveEventSource` passes `apiVersion: .v2`
//  explicitly (#749): whether that source is actually wired in is now the
//  conjunction `apiVersion.supportsLiveUpdates && callerOptedIn`, so omitting
//  the version falls through to `PlaylistAPIVersion.loadActive()` — which
//  resolves to `.v1` (no PostHog flag, no manual override) in a test process
//  — and the source would silently never connect. These tests are about the
//  SSE-mechanics once a subscription IS active, so they force the version
//  that has one rather than relying on `loadActive()`'s default. Don't
//  "simplify" this back out.
//
//  Created by Jake Bromberg on 07/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import PlaylistTesting
@testable import Playlist
@testable import Caching

@MainActor
@Suite("PlaylistService live updates", .serialized)
struct PlaylistServiceLiveUpdatesTests {

    /// Polls `condition` until it holds or `timeout` elapses. Used to await a
    /// side effect (a reconnect) that produces no broadcast to await on.
    private func waitUntil(
        _ timeout: Duration = .seconds(2),
        _ condition: @Sendable () async -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return await condition()
    }

    @Test("An insert event appends the new playcut", .timeLimit(.minutes(1)))
    func insertAppends() async throws {
        let fetcher = MockPlaylistFetcher()
        fetcher.playlistToReturn = .stub(playcuts: [.stub(id: 1, chronOrderID: 1)])
        let source = MockLiveFsEventSource(events: [
            .insert(.stub(id: 2, chronOrderID: 2, songTitle: "Back, Baby", artistName: "Jessica Pratt"))
        ])
        let service = PlaylistService(
            fetcher: fetcher, interval: 3600,
            cacheCoordinator: makeTestCacheCoordinator(), liveEventSource: source,
            apiVersion: .v2
        )

        var iterator = service.updates().makeAsyncIterator()
        #expect(await iterator.next()?.playcuts.map(\.id) == [1])
        await service.setForegrounded(true)

        let afterInsert = await iterator.next()
        #expect(afterInsert?.playcuts.map(\.id).sorted() == [1, 2])
        let inserted = afterInsert?.playcuts.first { $0.id == 2 }
        #expect(inserted?.artistName == "Jessica Pratt")
    }

    @Test("An update event replaces the matching row by id, merging enrichment", .timeLimit(.minutes(1)))
    func updateReplacesById() async throws {
        let fetcher = MockPlaylistFetcher()
        fetcher.playlistToReturn = .stub(playcuts: [.stub(id: 1, chronOrderID: 1, metadataStatus: .pending)])
        let enriched = Playcut.stub(
            id: 1, chronOrderID: 1,
            artworkURL: URL(string: "https://example.com/art.jpg"),
            metadataStatus: .enrichedMatch
        )
        let source = MockLiveFsEventSource(events: [.update(enriched)])
        let service = PlaylistService(
            fetcher: fetcher, interval: 3600,
            cacheCoordinator: makeTestCacheCoordinator(), liveEventSource: source,
            apiVersion: .v2
        )

        var iterator = service.updates().makeAsyncIterator()
        #expect(await iterator.next()?.playcuts.map(\.id) == [1])
        await service.setForegrounded(true)

        let afterUpdate = await iterator.next()
        // Still exactly one row (replaced, not appended)...
        #expect(afterUpdate?.playcuts.map(\.id) == [1])
        // ...now carrying the enrichment.
        let row = afterUpdate?.playcuts.first
        #expect(row?.metadataStatus == .enrichedMatch)
        #expect(row?.artworkURL == URL(string: "https://example.com/art.jpg"))
    }

    @Test("An update for an id not yet present appends (out-of-order delivery)", .timeLimit(.minutes(1)))
    func outOfOrderUpdateAppends() async throws {
        let fetcher = MockPlaylistFetcher()
        fetcher.playlistToReturn = .stub(playcuts: [.stub(id: 1, chronOrderID: 1)])
        let source = MockLiveFsEventSource(events: [
            .update(.stub(id: 5, chronOrderID: 5, metadataStatus: .enrichedMatch))
        ])
        let service = PlaylistService(
            fetcher: fetcher, interval: 3600,
            cacheCoordinator: makeTestCacheCoordinator(), liveEventSource: source,
            apiVersion: .v2
        )

        var iterator = service.updates().makeAsyncIterator()
        #expect(await iterator.next()?.playcuts.map(\.id) == [1])
        await service.setForegrounded(true)

        let afterUpdate = await iterator.next()
        #expect(afterUpdate?.playcuts.map(\.id).sorted() == [1, 5])
    }

    @Test("A duplicate insert is idempotent — no duplicate row, no extra broadcast", .timeLimit(.minutes(1)))
    func duplicateInsertIsIdempotent() async throws {
        let fetcher = MockPlaylistFetcher()
        fetcher.playlistToReturn = .stub(playcuts: [.stub(id: 1, chronOrderID: 1)])
        let inserted = Playcut.stub(id: 2, chronOrderID: 2)
        // The same row twice, then a distinct third row. The duplicate must not
        // produce its own broadcast, so the next broadcast after the first
        // insert is the id-3 row, proving id 2 wasn't re-broadcast.
        let source = MockLiveFsEventSource(events: [
            .insert(inserted),
            .insert(inserted),
            .insert(.stub(id: 3, chronOrderID: 3)),
        ])
        let service = PlaylistService(
            fetcher: fetcher, interval: 3600,
            cacheCoordinator: makeTestCacheCoordinator(), liveEventSource: source,
            apiVersion: .v2
        )

        var iterator = service.updates().makeAsyncIterator()
        #expect(await iterator.next()?.playcuts.map(\.id) == [1])
        await service.setForegrounded(true)

        let first = await iterator.next()
        #expect(first?.playcuts.map(\.id).sorted() == [1, 2])
        let second = await iterator.next()
        #expect(second?.playcuts.map(\.id).sorted() == [1, 2, 3])
    }

    @Test("A refetch event triggers a full reconciliation fetch", .timeLimit(.minutes(1)))
    func refetchTriggersFetch() async throws {
        let fetcher = MockPlaylistFetcher()
        fetcher.playlistToReturn = .stub(playcuts: [.stub(id: 1, chronOrderID: 1)])
        let source = MockLiveFsEventSource(events: [.refetch(source: "etl")])
        let service = PlaylistService(
            fetcher: fetcher, interval: 3600,
            cacheCoordinator: makeTestCacheCoordinator(), liveEventSource: source,
            apiVersion: .v2
        )

        var iterator = service.updates().makeAsyncIterator()
        #expect(await iterator.next()?.playcuts.map(\.id) == [1])
        // The refetch will pull this newer snapshot.
        fetcher.playlistToReturn = .stub(playcuts: [
            .stub(id: 1, chronOrderID: 1),
            .stub(id: 9, chronOrderID: 9),
        ])
        await service.setForegrounded(true)

        let afterRefetch = await iterator.next()
        #expect(afterRefetch?.playcuts.map(\.id).sorted() == [1, 9])
        #expect(fetcher.callCount >= 2) // initial baseline poll + the refetch
    }

    @Test("Events are gated on foreground: nothing is applied until setForegrounded(true)", .timeLimit(.minutes(1)))
    func eventsGatedOnForeground() async throws {
        let fetcher = MockPlaylistFetcher()
        fetcher.playlistToReturn = .stub(playcuts: [.stub(id: 1, chronOrderID: 1)])
        let source = MockLiveFsEventSource(events: [.insert(.stub(id: 2, chronOrderID: 2))])
        let service = PlaylistService(
            fetcher: fetcher, interval: 3600,
            cacheCoordinator: makeTestCacheCoordinator(), liveEventSource: source,
            apiVersion: .v2
        )

        var iterator = service.updates().makeAsyncIterator()
        #expect(await iterator.next()?.playcuts.map(\.id) == [1])
        _ = iterator

        // Non-vacuity guard: `connectCount == 0` below must mean "foregrounding
        // gates the loop", not "no source is wired in at all". Drop the
        // `apiVersion: .v2` above and this fails, instead of the test quietly
        // degenerating into a duplicate of the v1-inertness test in
        // PlaylistServiceWiringTests.
        #expect(await service.wiringSnapshot().liveUpdatesActive)

        // The consume loop provably hasn't started (it starts only from
        // setForegrounded(true)), so the snapshot is the baseline alone and the
        // source was never connected.
        let snapshot = await service.currentPlaylistSnapshot()
        #expect(snapshot.playcuts.map(\.id) == [1])
        #expect(source.connectCount == 0)
    }

    @Test("Backgrounding tears down the subscription so a later foreground reconnects", .timeLimit(.minutes(1)))
    func backgroundingTearsDownSubscription() async throws {
        let fetcher = MockPlaylistFetcher()
        fetcher.playlistToReturn = .stub(playcuts: [.stub(id: 1, chronOrderID: 1)])
        // Stays open after the insert, modelling one live connection.
        let source = MockLiveFsEventSource(events: [.insert(.stub(id: 2, chronOrderID: 2))])
        let service = PlaylistService(
            fetcher: fetcher, interval: 3600,
            cacheCoordinator: makeTestCacheCoordinator(), liveEventSource: source,
            apiVersion: .v2
        )

        var iterator = service.updates().makeAsyncIterator()
        #expect(await iterator.next()?.playcuts.map(\.id) == [1])
        await service.setForegrounded(true)
        _ = await iterator.next() // insert applied — the first connection is live
        #expect(source.connectCount == 1)

        await service.setForegrounded(false)
        await service.setForegrounded(true)

        // A fresh subscription proves the backgrounded task was torn down (had it
        // survived, `liveUpdatesTask` would be non-nil and the guard would skip
        // reconnecting, leaving connectCount at 1).
        #expect(await waitUntil { source.connectCount == 2 })
    }

    @Test("setForegrounded is a no-op when live updates aren't enabled", .timeLimit(.minutes(1)))
    func noOpWhenLiveUpdatesDisabled() async throws {
        let fetcher = MockPlaylistFetcher()
        fetcher.playlistToReturn = .stub(playcuts: [.stub(id: 1, chronOrderID: 1)])
        // Convenience initializer, liveUpdatesEnabled defaults false → no source.
        let service = PlaylistService(
            fetcher: fetcher, interval: 3600,
            cacheCoordinator: makeTestCacheCoordinator()
        )

        var iterator = service.updates().makeAsyncIterator()
        #expect(await iterator.next()?.playcuts.map(\.id) == [1])
        _ = iterator
        // Toggling foreground must not disrupt the poll-only path.
        await service.setForegrounded(true)
        await service.setForegrounded(false)
        let snapshot = await service.currentPlaylistSnapshot()
        #expect(snapshot.playcuts.map(\.id) == [1])
    }

    @Test("A row below the current window is dropped, not appended", .timeLimit(.minutes(1)))
    func dropsRowBelowWindow() async throws {
        let fetcher = MockPlaylistFetcher()
        fetcher.playlistToReturn = .stub(playcuts: [
            .stub(id: 5_304_100, chronOrderID: 5_304_100),
            .stub(id: 5_304_110, chronOrderID: 5_304_110),
        ])
        // An archival enrichment row (#780): `live-fs-topic` carries a
        // full-catalog backfill whose ids sit millions below the live head. It
        // must not be broadcast, so the next broadcast after foregrounding is
        // the legitimate row — proving the archival one was dropped, exactly as
        // `duplicateInsertIsIdempotent` proves a duplicate isn't re-broadcast.
        let source = MockLiveFsEventSource(events: [
            .update(.stub(id: 639_857, chronOrderID: 639_857, metadataStatus: .enrichedMatch)),
            .insert(.stub(id: 5_304_111, chronOrderID: 5_304_111)),
        ])
        let service = PlaylistService(
            fetcher: fetcher, interval: 3600,
            cacheCoordinator: makeTestCacheCoordinator(), liveEventSource: source,
            apiVersion: .v2
        )

        var iterator = service.updates().makeAsyncIterator()
        #expect(await iterator.next()?.playcuts.map(\.id) == [5_304_100, 5_304_110])
        await service.setForegrounded(true)

        let next = await iterator.next()
        #expect(next?.playcuts.map(\.id).sorted() == [5_304_100, 5_304_110, 5_304_111])
    }

    @Test("With an empty window there is no floor, so a row is still accepted", .timeLimit(.minutes(1)))
    func acceptsRowWhenWindowIsEmpty() async throws {
        let fetcher = MockPlaylistFetcher()
        // A content-empty fetch leaves no rows to derive a floor from; the event
        // is the only data there is, and the next poll reconciles regardless.
        fetcher.playlistToReturn = .stub(playcuts: [])
        let source = MockLiveFsEventSource(events: [.insert(.stub(id: 42, chronOrderID: 42))])
        let service = PlaylistService(
            fetcher: fetcher, interval: 3600,
            cacheCoordinator: makeTestCacheCoordinator(), liveEventSource: source,
            apiVersion: .v2
        )

        var iterator = service.updates().makeAsyncIterator()
        await service.setForegrounded(true)

        // Await the broadcast rather than polling a snapshot on a wall-clock
        // budget: the content-empty fetch equals `currentPlaylist` and so
        // broadcasts nothing, leaving the accepted insert as the only thing
        // that can wake this iterator. A guard that wrongly dropped the row
        // would hang here until the test's time limit rather than racing it.
        var received: [UInt64] = []
        while received.isEmpty {
            received = await iterator.next()?.playcuts.map(\.id) ?? []
        }
        #expect(received == [42])
    }
}
