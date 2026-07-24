//
//  PlaylistServiceMetadataTransitionsTests.swift
//  Playlist
//
//  Verifies PlaylistService.terminalMetadataTransitions(): a playcut is yielded
//  exactly once when its metadataStatus first transitions into a terminal
//  enrichment state (MetadataStatus.isTerminal), and non-terminal transitions
//  (nil -> pending -> enriching) are not yielded. This is the observation seam
//  Spotlight re-donation (issue #443) hangs off of.
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import PlaylistTesting
@testable import Playlist
@testable import Caching

@MainActor
@Suite("PlaylistService metadata transitions", .serialized)
struct PlaylistServiceMetadataTransitionsTests {

    @Test("Terminal transition on a previously non-terminal row is yielded exactly once", .timeLimit(.minutes(1)))
    func yieldsOnTerminalTransition() async throws {
        let mockFetcher = MockPlaylistFetcher()
        mockFetcher.playlistToReturn = .stub(playcuts: [.stub(id: 1, chronOrderID: 1, metadataStatus: .pending)])

        let service = PlaylistService(fetcher: mockFetcher, interval: 0.05, cacheCoordinator: makeTestCacheCoordinator())

        var transitions = service.terminalMetadataTransitions().makeAsyncIterator()
        var iterator = service.updates().makeAsyncIterator()

        // Prime the pump so the pending row is seen once (no transition yet).
        _ = await iterator.next()

        // Enrichment lands: pending -> enrichedMatch.
        mockFetcher.playlistToReturn = .stub(playcuts: [
            .stub(id: 1, chronOrderID: 1, artworkURL: URL(string: "https://example.com/art.jpg"), metadataStatus: .enrichedMatch)
        ])
        _ = await iterator.next()

        let transitioned = await transitions.next()
        #expect(transitioned?.id == 1)
        #expect(transitioned?.metadataStatus == .enrichedMatch)
    }

    @Test("Non-terminal transitions are not yielded", .timeLimit(.minutes(1)))
    func doesNotYieldOnNonTerminalTransition() async throws {
        let mockFetcher = MockPlaylistFetcher()
        mockFetcher.playlistToReturn = .stub(playcuts: [.stub(id: 1, chronOrderID: 1, metadataStatus: .pending)])

        let service = PlaylistService(fetcher: mockFetcher, interval: 0.05, cacheCoordinator: makeTestCacheCoordinator())

        var transitions = service.terminalMetadataTransitions()
            .prefix(1)
            .makeAsyncIterator()
        var iterator = service.updates().makeAsyncIterator()

        _ = await iterator.next()

        // pending -> enriching: still not terminal.
        mockFetcher.playlistToReturn = .stub(playcuts: [.stub(id: 1, chronOrderID: 1, metadataStatus: .enriching)])
        _ = await iterator.next()

        // enriching -> enrichedMatch: the only terminal transition in this run.
        mockFetcher.playlistToReturn = .stub(playcuts: [
            .stub(id: 1, chronOrderID: 1, artworkURL: URL(string: "https://example.com/art.jpg"), metadataStatus: .enrichedMatch)
        ])
        _ = await iterator.next()

        // Exactly one terminal transition reaches the stream, and it's the
        // enrichedMatch one, not the earlier non-terminal `enriching` change.
        let onlyTransition = await transitions.next()
        #expect(onlyTransition?.metadataStatus == .enrichedMatch)
    }

    @Test("A warm launch seeds the cached enriched window as baseline without yielding", .timeLimit(.minutes(1)))
    func warmLaunchSeedsBaselineWithoutYielding() async throws {
        // Warm launch: the cache already holds an already-enriched (terminal)
        // window. The first snapshot the transitions stream sees is this cached
        // window against an empty diff map — the exact condition that used to
        // re-donate the entire enriched window at every launch (issue #443).
        let coordinator = makeTestCacheCoordinator()
        let cachedEnriched = Playlist.stub(playcuts: [
            .stub(id: 1, chronOrderID: 1, artworkURL: URL(string: "https://example.com/1.jpg"), metadataStatus: .enrichedMatch),
            .stub(id: 2, chronOrderID: 2, artworkURL: URL(string: "https://example.com/2.jpg"), metadataStatus: .enrichedNoMatch),
        ])
        await coordinator.set(value: cachedEnriched, for: PlaylistCacheKey.playlist, lifespan: 15 * 60)

        let mockFetcher = MockPlaylistFetcher()
        // First fetch: same enriched window plus a brand-new pending row.
        mockFetcher.playlistToReturn = .stub(playcuts: cachedEnriched.playcuts + [
            .stub(id: 3, chronOrderID: 3, metadataStatus: .pending)
        ])

        let service = PlaylistService(fetcher: mockFetcher, interval: 0.05, cacheCoordinator: coordinator)

        var transitions = service.terminalMetadataTransitions().makeAsyncIterator()
        var iterator = service.updates().makeAsyncIterator()

        // Warm cache load yields the enriched window immediately: baseline seed,
        // no yield for rows 1 or 2.
        _ = await iterator.next()
        // Fetch loop picks up the new pending row 3 (still non-terminal).
        _ = await iterator.next()

        // Sentinel: row 3 enriches. This is the ONLY genuine transition into a
        // terminal state in this run.
        mockFetcher.playlistToReturn = .stub(playcuts: cachedEnriched.playcuts + [
            .stub(id: 3, chronOrderID: 3, artworkURL: URL(string: "https://example.com/3.jpg"), metadataStatus: .enrichedMatch)
        ])
        _ = await iterator.next()

        // The first (and only) emission is row 3. If the cached baseline had been
        // re-donated, the first emission would be row 1 or 2 instead.
        let first = await transitions.next()
        #expect(first?.id == 3)
        #expect(first?.metadataStatus == .enrichedMatch)
    }

    @Test("A change between two terminal states is not yielded", .timeLimit(.minutes(1)))
    func terminalToTerminalTransitionIsNotYielded() async throws {
        let mockFetcher = MockPlaylistFetcher()
        mockFetcher.playlistToReturn = .stub(playcuts: [.stub(id: 1, chronOrderID: 1, metadataStatus: .pending)])

        let service = PlaylistService(fetcher: mockFetcher, interval: 0.05, cacheCoordinator: makeTestCacheCoordinator())

        var transitions = service.terminalMetadataTransitions().makeAsyncIterator()
        var iterator = service.updates().makeAsyncIterator()

        // Baseline: row 1 pending.
        _ = await iterator.next()

        // 1: pending -> enrichedMatch (the one genuine transition into terminal).
        mockFetcher.playlistToReturn = .stub(playcuts: [.stub(id: 1, chronOrderID: 1, metadataStatus: .enrichedMatch)])
        _ = await iterator.next()

        // 1: enrichedMatch -> enrichedNoMatch (terminal -> terminal: must NOT yield).
        mockFetcher.playlistToReturn = .stub(playcuts: [.stub(id: 1, chronOrderID: 1, metadataStatus: .enrichedNoMatch)])
        _ = await iterator.next()

        // Sentinel: a new row 2 lands terminal. If the terminal->terminal change
        // on row 1 had wrongly yielded, the second emission would be row 1's
        // enrichedNoMatch rather than row 2's landing.
        mockFetcher.playlistToReturn = .stub(playcuts: [
            .stub(id: 1, chronOrderID: 1, metadataStatus: .enrichedNoMatch),
            .stub(id: 2, chronOrderID: 2, metadataStatus: .pending),
        ])
        _ = await iterator.next()
        mockFetcher.playlistToReturn = .stub(playcuts: [
            .stub(id: 1, chronOrderID: 1, metadataStatus: .enrichedNoMatch),
            .stub(id: 2, chronOrderID: 2, artworkURL: URL(string: "https://example.com/2.jpg"), metadataStatus: .enrichedMatch),
        ])
        _ = await iterator.next()

        let firstEmit = await transitions.next()
        #expect(firstEmit?.id == 1)
        #expect(firstEmit?.metadataStatus == .enrichedMatch)

        let secondEmit = await transitions.next()
        #expect(secondEmit?.id == 2)
        #expect(secondEmit?.metadataStatus == .enrichedMatch)
    }
}
