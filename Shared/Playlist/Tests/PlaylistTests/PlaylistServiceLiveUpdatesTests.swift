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
//  Every test injects a `liveEventSource` directly; wiring it in is now solely
//  the caller's opt-in (#262). See `MockLiveFsEventSource` for the
//  simulator-override hazard that removal eliminated.
//
//  Created by Jake Bromberg on 07/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import Synchronization
import CoreTesting
import PlaylistTesting
@testable import Playlist
@testable import Caching

@MainActor
@Suite("PlaylistService live updates", .serialized)
struct PlaylistServiceLiveUpdatesTests {

    @Test("An insert event appends the new playcut", .timeLimit(.minutes(1)))
    func insertAppends() async throws {
        let fetcher = MockPlaylistFetcher()
        fetcher.playlistToReturn = .stub(playcuts: [.stub(id: 1, chronOrderID: 1)])
        let source = MockLiveFsEventSource(events: [
            .insert(.stub(id: 2, chronOrderID: 2, songTitle: "Back, Baby", artistName: "Jessica Pratt"))
        ])
        let service = PlaylistService(
            fetcher: fetcher, interval: 3600,
            cacheCoordinator: makeTestCacheCoordinator(), liveEventSource: source
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
            cacheCoordinator: makeTestCacheCoordinator(), liveEventSource: source
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

    @Test("An update whose key derivation fell back to the bare id keeps the stored packed key", .timeLimit(.minutes(1)))
    func updateKeepsStoredPackedKeyOnBareIDFallback() async throws {
        // `FlowsheetEntry.show_id` is optional, so an SSE update payload that
        // omitted it (a Backend projection regression, a partial deploy)
        // decodes cleanly and re-derives the row's key as the bare-id
        // fallback. A wholesale replace would sink the on-air song to the
        // bottom of the feed mid-play; the stored key was derived from a
        // payload that DID carry the composite, so it stays authoritative
        // while the enrichment lands.
        let packedKey = UInt64(42) << 32 | 9
        let fetcher = MockPlaylistFetcher()
        fetcher.playlistToReturn = .stub(playcuts: [
            .stub(id: 5_304_111, chronOrderID: packedKey, metadataStatus: .pending)
        ])
        let source = MockLiveFsEventSource(events: [
            .update(.stub(
                id: 5_304_111, chronOrderID: 5_304_111,
                artworkURL: URL(string: "https://example.com/art.jpg"),
                albumId: 4417,
                metadataStatus: .enrichedMatch
            ))
        ])
        let service = PlaylistService(
            fetcher: fetcher, interval: 3600,
            cacheCoordinator: makeTestCacheCoordinator(), liveEventSource: source
        )

        var iterator = service.updates().makeAsyncIterator()
        #expect(await iterator.next()?.playcuts.map(\.id) == [5_304_111])
        await service.setForegrounded(true)

        let afterUpdate = await iterator.next()
        let row = afterUpdate?.playcuts.first
        // The enrichment lands, with every other incoming field...
        #expect(row?.metadataStatus == .enrichedMatch)
        #expect(row?.artworkURL == URL(string: "https://example.com/art.jpg"))
        #expect(row?.albumId == 4417)
        // ...but the ordering key is not downgraded to the bare id.
        #expect(row?.chronOrderID == packedKey)
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
            cacheCoordinator: makeTestCacheCoordinator(), liveEventSource: source
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
            cacheCoordinator: makeTestCacheCoordinator(), liveEventSource: source
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
            cacheCoordinator: makeTestCacheCoordinator(), liveEventSource: source
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
            cacheCoordinator: makeTestCacheCoordinator(), liveEventSource: source
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
            cacheCoordinator: makeTestCacheCoordinator(), liveEventSource: source
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
        #expect(await waitUntil(timeout: .seconds(2)) { source.connectCount == 2 })
    }

    @Test("A superseded consume loop does not retire the loop that replaced it", .timeLimit(.minutes(1)))
    func supersededLoopLeavesTheLiveOneRegistered() async throws {
        let fetcher = MockPlaylistFetcher()
        fetcher.playlistToReturn = .stub(playcuts: [.stub(id: 1, chronOrderID: 1)])
        let source = MockLiveFsEventSource(events: [.insert(.stub(id: 2, chronOrderID: 2))])
        let service = PlaylistService(
            fetcher: fetcher, interval: 3600,
            cacheCoordinator: makeTestCacheCoordinator(), liveEventSource: source
        )

        var iterator = service.updates().makeAsyncIterator()
        #expect(await iterator.next()?.playcuts.map(\.id) == [1])
        await service.setForegrounded(true)
        _ = await iterator.next()

        // Background then foreground: the first loop is cancelled and a second
        // registers itself. The first loop's teardown runs afterwards, and must
        // recognise that `liveUpdatesTask` no longer refers to it — clearing it
        // there would orphan the live loop and let a third start alongside it.
        await service.setForegrounded(false)
        await service.setForegrounded(true)
        #expect(await waitUntil(timeout: .seconds(2)) { source.connectCount == 2 })

        // Give the superseded loop every opportunity to run its teardown.
        for _ in 0..<50 { await Task.yield() }

        let snapshot = await service.wiringSnapshot()
        #expect(snapshot.hasLiveUpdatesTask)
        #expect(snapshot.liveUpdatesActive)
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
            cacheCoordinator: makeTestCacheCoordinator(), liveEventSource: source
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
            cacheCoordinator: makeTestCacheCoordinator(), liveEventSource: source
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

// MARK: - on_air catch-up refresh (#1197)

private func show(_ id: UInt64) -> OnAir {
    .dj("Cat Power Hour", show: OnAirShow(id: id, title: nil, specialty: nil))
}

/// Closes the live-event script: it is stored and broadcast last, after every case row,
/// and carries no show id, so it can never trigger a refresh itself.
private let sentinelID: UInt64 = 999

struct OnAirRefreshCase: Sendable, CustomTestStringConvertible {
    let name: String
    let stored: [Playcut]
    let onAir: OnAir
    let events: [LiveFsEvent]
    /// Fetches beyond the initial baseline poll.
    let expectedRefreshes: Int
    var testDescription: String { name }
}

private let onAirRefreshCases: [OnAirRefreshCase] = [
    OnAirRefreshCase(name: "inserted row from a newer show than on_air names", stored: [.stub(id: 1, showID: 42)], onAir: show(42), events: [.insert(.stub(id: 2, showID: 43))], expectedRefreshes: 1),
    OnAirRefreshCase(name: "updated row from a newer show than on_air names", stored: [.stub(id: 1, showID: 42)], onAir: show(42), events: [.update(.stub(id: 2, showID: 43))], expectedRefreshes: 1),
    OnAirRefreshCase(name: "newer show while on_air is unknown", stored: [.stub(id: 1, showID: 42)], onAir: .unknown, events: [.insert(.stub(id: 2, showID: 43))], expectedRefreshes: 1),
    OnAirRefreshCase(name: "newer show during automation", stored: [.stub(id: 1, showID: 42)], onAir: .automation, events: [.insert(.stub(id: 2, showID: 43))], expectedRefreshes: 1),
    OnAirRefreshCase(name: "row from the open show when only the open show is newer than the stored rows", stored: [.stub(id: 1, showID: 42)], onAir: show(43), events: [.insert(.stub(id: 2, showID: 43))], expectedRefreshes: 0),
    OnAirRefreshCase(name: "row from the open show", stored: [.stub(id: 1, showID: 42)], onAir: show(42), events: [.insert(.stub(id: 2, showID: 42))], expectedRefreshes: 0),
    OnAirRefreshCase(name: "row from an older show", stored: [.stub(id: 5, showID: 42)], onAir: show(42), events: [.insert(.stub(id: 6, showID: 41))], expectedRefreshes: 0),
    OnAirRefreshCase(name: "row with no show id", stored: [.stub(id: 1, showID: 42)], onAir: show(42), events: [.insert(.stub(id: 2))], expectedRefreshes: 0),
    OnAirRefreshCase(name: "update with no show id", stored: [.stub(id: 1, showID: 42)], onAir: show(42), events: [.update(.stub(id: 1, songTitle: "Back, Baby"))], expectedRefreshes: 0),
    OnAirRefreshCase(name: "automation enrichment updates for the previous show", stored: [.stub(id: 1, showID: 42), .stub(id: 2, showID: 42)], onAir: .automation, events: [.update(.stub(id: 1, showID: 42, songTitle: "Back, Baby")), .update(.stub(id: 2, showID: 42, songTitle: "Call Your Name")), .update(.stub(id: 1, showID: 41, songTitle: "In a Sentimental Mood"))], expectedRefreshes: 0),
    OnAirRefreshCase(name: "no show id known anywhere", stored: [.stub(id: 1)], onAir: .unknown, events: [.insert(.stub(id: 2, showID: 43))], expectedRefreshes: 1),
]

/// A source whose events the test pushes one at a time, so a row can arrive after an
/// earlier refresh has settled. Yields nothing until ``push(_:)``.
private final class PushableLiveFsEventSource: LiveFsEventSource, @unchecked Sendable {
    private let stream: AsyncStream<LiveFsEvent>
    private let continuation: AsyncStream<LiveFsEvent>.Continuation

    init() { (stream, continuation) = AsyncStream.makeStream() }

    func push(_ event: LiveFsEvent) { continuation.yield(event) }
    func connect() -> AsyncStream<LiveFsEvent> { stream }
}

/// Serves `baseline` for the first poll, then fails (`.empty`, as the real fetcher folds
/// every error) for `failures` refreshes, then serves `recovered`.
private final class FailThenRecoverFetcher: PlaylistFetcherProtocol, @unchecked Sendable {
    private let baseline: Playlist
    private let recovered: Playlist
    private let failures: Int
    private let calls = Mutex(0)

    init(baseline: Playlist, recovered: Playlist, failures: Int) {
        self.baseline = baseline
        self.recovered = recovered
        self.failures = failures
    }

    var callCount: Int { calls.withLock { $0 } }

    func fetchPlaylist() async -> Playlist {
        let call = calls.withLock { value -> Int in value += 1; return value }
        if call == 1 { return baseline }
        return call - 1 <= failures ? .empty : recovered
    }
}

struct OnAirRetryCase: Sendable, CustomTestStringConvertible {
    let name: String
    let spacing: Duration
    /// Refreshes that fail before one succeeds.
    let failures: Int
    /// Show-43 rows pushed, one at a time, after the first row's refresh has settled.
    let laterRows: Int
    /// Fetches beyond the initial baseline poll.
    let expectedRefreshes: Int
    var testDescription: String { name }
}

private let onAirRetryCases: [OnAirRetryCase] = [
    OnAirRetryCase(name: "failed refresh is retried by the next row of the same show", spacing: .zero, failures: 1, laterRows: 1, expectedRefreshes: 2),
    OnAirRetryCase(name: "successful retry absorbs the rows after it", spacing: .zero, failures: 1, laterRows: 4, expectedRefreshes: 2),
    OnAirRetryCase(name: "rows within the spacing after a failure do not retry", spacing: .seconds(3600), failures: 1, laterRows: 4, expectedRefreshes: 1),
    OnAirRetryCase(name: "no later row means no retry", spacing: .zero, failures: 1, laterRows: 0, expectedRefreshes: 1),
]

/// Returns the baseline poll at once and holds every later fetch until ``open()``,
/// so a test can observe the service while a refresh is in flight. An actor, so the
/// service's refresh task and the test body never race on its state.
private actor GatedPlaylistFetcher: PlaylistFetcherProtocol {
    private let playlistToReturn: Playlist
    private(set) var callCount = 0
    private var isOpen = false

    init(playlistToReturn: Playlist) { self.playlistToReturn = playlistToReturn }

    func open() { isOpen = true }

    func fetchPlaylist() async -> Playlist {
        callCount += 1
        if callCount > 1 {
            while !isOpen { try? await Task.sleep(for: .milliseconds(1)) }
        }
        return playlistToReturn
    }
}

extension PlaylistServiceLiveUpdatesTests {
    @Test("A live row newer than the known show refreshes on_air once; anything else does not", arguments: onAirRefreshCases)
    func onAirRefresh(_ testCase: OnAirRefreshCase) async throws {
        let sentinel = Playcut.stub(id: sentinelID)
        let fetcher = MockPlaylistFetcher()
        fetcher.playlistToReturn = .stub(playcuts: testCase.stored, onAir: testCase.onAir)
        let source = MockLiveFsEventSource(events: testCase.events + [.insert(sentinel)])
        let service = PlaylistService(
            fetcher: fetcher, interval: 3600,
            cacheCoordinator: makeTestCacheCoordinator(), liveEventSource: source
        )

        var iterator = service.updates().makeAsyncIterator()
        _ = await iterator.next()
        let baseline = fetcher.callCount
        await service.setForegrounded(true)

        // Read broadcasts until the sentinel row shows up, i.e. every earlier event has been
        // applied, then let any refresh those events started reach the fetcher.
        while await iterator.next()?.playcuts.contains(where: { $0.id == sentinelID }) != true {}
        for _ in 0..<50 { await Task.yield() }
        if testCase.expectedRefreshes > 0 {
            #expect(await waitUntil(timeout: .seconds(2)) { fetcher.callCount == baseline + testCase.expectedRefreshes })
            for _ in 0..<50 { await Task.yield() }
        }
        #expect(fetcher.callCount == baseline + testCase.expectedRefreshes)
    }

    @Test("A failed on_air refresh is retried by a later row of the same show, bounded by the spacing", arguments: onAirRetryCases)
    func onAirRefreshRetry(_ testCase: OnAirRetryCase) async throws {
        let baseline = Playlist.stub(playcuts: [.stub(id: 1, showID: 42)], onAir: show(42))
        let fetcher = FailThenRecoverFetcher(
            baseline: baseline,
            recovered: .stub(playcuts: [.stub(id: 1, showID: 42), .stub(id: 2, showID: 43)], onAir: show(43)),
            failures: testCase.failures
        )
        let source = PushableLiveFsEventSource()
        let service = PlaylistService(
            fetcher: fetcher, interval: 3600,
            cacheCoordinator: makeTestCacheCoordinator(), liveEventSource: source,
            onAirRetrySpacing: testCase.spacing
        )

        var iterator = service.updates().makeAsyncIterator()
        _ = await iterator.next()
        await service.setForegrounded(true)

        // Each row is let settle before the next, so no row lands while a refresh is in flight.
        for id in 2...UInt64(2 + testCase.laterRows) {
            source.push(.insert(.stub(id: id, showID: 43)))
            if id == 2 {
                #expect(await waitUntil(timeout: .seconds(2)) { fetcher.callCount == 2 })
            }
            for _ in 0..<100 { await Task.yield() }
        }
        #expect(await waitUntil(timeout: .seconds(2)) { fetcher.callCount == 1 + testCase.expectedRefreshes })
        for _ in 0..<100 { await Task.yield() }
        #expect(fetcher.callCount == 1 + testCase.expectedRefreshes)
    }

    @Test("A burst of rows naming a show while none is known starts one refresh", .timeLimit(.minutes(1)))
    func unknownBaselineBurstCoalesces() async throws {
        let sentinel = Playcut.stub(id: sentinelID)
        let fetcher = GatedPlaylistFetcher(playlistToReturn: .stub(playcuts: [.stub(id: 1)], onAir: .unknown))
        let source = MockLiveFsEventSource(events: [
            .insert(.stub(id: 2, showID: 43)), .insert(.stub(id: 3, showID: 43)), .insert(sentinel),
        ])
        let service = PlaylistService(
            fetcher: fetcher, interval: 3600,
            cacheCoordinator: makeTestCacheCoordinator(), liveEventSource: source
        )

        var iterator = service.updates().makeAsyncIterator()
        _ = await iterator.next()
        await service.setForegrounded(true)
        while await iterator.next()?.playcuts.contains(where: { $0.id == sentinelID }) != true {}
        for _ in 0..<50 { await Task.yield() }
        #expect(await fetcher.callCount == 2) // the baseline plus the one held refresh
    }

    @Test("Rows that arrive while an on_air refresh is in flight are absorbed by it", .timeLimit(.minutes(1)))
    func inFlightRefreshCoalesces() async throws {
        let sentinel = Playcut.stub(id: sentinelID)
        let fetcher = GatedPlaylistFetcher(playlistToReturn: .stub(playcuts: [.stub(id: 1, showID: 42)], onAir: show(42)))
        let source = MockLiveFsEventSource(events: [
            .insert(.stub(id: 2, showID: 43)), .insert(.stub(id: 3, showID: 44)), .insert(sentinel),
        ])
        let service = PlaylistService(
            fetcher: fetcher, interval: 3600,
            cacheCoordinator: makeTestCacheCoordinator(), liveEventSource: source
        )

        var iterator = service.updates().makeAsyncIterator()
        _ = await iterator.next()
        await service.setForegrounded(true)

        // Read broadcasts until the sentinel row shows up, i.e. every earlier event has been
        // applied, then let any refresh those events started reach the fetcher.
        while await iterator.next()?.playcuts.contains(where: { $0.id == sentinelID }) != true {}
        for _ in 0..<50 { await Task.yield() }
        #expect(await fetcher.callCount == 2) // the baseline plus the one held refresh
        await fetcher.open()
        // The released refresh ingests [row 1], which differs from the live window, so its
        // broadcast is the completion signal; a trailing refresh would fetch after it.
        _ = await iterator.next()
        for _ in 0..<50 { await Task.yield() }
        #expect(await fetcher.callCount == 2)
    }

    @Test("A finished on_air refresh releases the latch so a later newer show refreshes again", .timeLimit(.minutes(1)))
    func finishedRefreshReleasesLatch() async throws {
        // Every refresh returns a window still on show 42, so the stream's replay of the
        // show-43 row after the reconnect backoff is newer than anything known and must
        // trigger a second refresh, which only happens once the first one released the latch.
        let fetcher = MockPlaylistFetcher()
        fetcher.playlistToReturn = .stub(playcuts: [.stub(id: 1, showID: 42)], onAir: show(42))
        let source = MockLiveFsEventSource(events: [.insert(.stub(id: 2, showID: 43))], finishesAfterScript: true)
        let service = PlaylistService(
            fetcher: fetcher, interval: 3600,
            cacheCoordinator: makeTestCacheCoordinator(), liveEventSource: source
        )

        var iterator = service.updates().makeAsyncIterator()
        _ = await iterator.next()
        let baseline = fetcher.callCount
        await service.setForegrounded(true)

        #expect(await waitUntil(timeout: .seconds(10)) { fetcher.callCount >= baseline + 2 })
    }
}
