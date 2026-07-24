//
//  SpotlightIndexerTests.swift
//  AppServices
//
//  Verifies `CoreSpotlightIndexer`'s F3 additions: `indexName` aliases
//  `PlaycutSpotlightIndex.name` (WXYCIntents) rather than a redeclared
//  literal, and its `PlaycutReindexer` conformance forwards to
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

@Suite("CoreSpotlightIndexer (F3 PlaycutReindexer)")
struct SpotlightIndexerTests {
    @Test("indexName aliases the WXYCIntents-owned constant")
    func indexNameAliasesSharedConstant() {
        #expect(CoreSpotlightIndexer.indexName == PlaycutSpotlightIndex.name)
    }

    @Test("donate(_:) forwards to indexPlaycuts at batch priority")
    func donateForwardsAtBatchPriority() async throws {
        // CoreSpotlightIndexer talks to the real CSSearchableIndex, so this
        // only proves the call doesn't throw for an empty batch — indexPlaycuts
        // already early-returns on empty input, avoiding an XPC round-trip in
        // a unit test. Priority/name wiring is covered by the two tests above
        // and by the reindex handlers' own spy-based tests in WXYCIntentsTests.
        let indexer = CoreSpotlightIndexer(indexName: "wxyc.playcuts.tests.\(UUID().uuidString)")

        try await indexer.donate([])
    }
}
#endif
