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
}
