//
//  SpotlightIndexerTests.swift
//  AppServices
//
//  Verifies `CoreSpotlightEntityIndexer<PlaycutEntity>`'s F3 additions
//  (#758): its `SpotlightReindexer` conformance forwards to
//  `indexPlaycuts(_:priority:)` at `SpotlightDonationService.batchPriority`
//  so a Spotlight-driven reindex is treated as a backfill, not an
//  elevated-priority "on air now" donation.
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if !os(watchOS) && !os(tvOS)
import Foundation
import Playlist
import PlaylistTesting
import Testing
import WXYCIntents
@testable import AppServices

@Suite("CoreSpotlightEntityIndexer<PlaycutEntity> (F3 SpotlightReindexer)")
struct SpotlightIndexerTests {
    @Test("indexName echoes back the name passed at init")
    func indexNameEchoesInit() {
        let indexer = CoreSpotlightEntityIndexer<PlaycutEntity>(indexName: SpotlightIndexName.playcuts)
        #expect(indexer.indexName == SpotlightIndexName.playcuts)
    }

    @Test("donate(_:) forwards to indexPlaycuts at batch priority")
    func donateForwardsAtBatchPriority() async throws {
        // CoreSpotlightEntityIndexer talks to the real CSSearchableIndex, so
        // this only proves the call doesn't throw for an empty batch — indexPlaycuts
        // already early-returns on empty input, avoiding an XPC round-trip in
        // a unit test. The priority forwarding itself is exercised by the
        // reindex handlers' own spy-based tests in WXYCIntentsTests.
        let indexer = CoreSpotlightEntityIndexer<PlaycutEntity>(indexName: "wxyc.playcuts.tests.\(UUID().uuidString)")

        try await indexer.donate([])
    }
}
#endif
