//
//  PlaylistServiceWiringTests.swift
//  Playlist
//
//  Verifies PlaylistService derives its poll interval and SSE wiring from the
//  caller's live-updates opt-in, including the watchOS/tvOS "stay poll-only"
//  regression guard. See WXYC/wxyc-ios-64#749.
//
//  The v1 half of this suite went with the v1 path in #262 — see the note on
//  `liveUpdatesDerivationCases` at the bottom of this file.
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import CoreTesting
import PlaylistTesting
@testable import Playlist
@testable import Caching

@MainActor
@Suite("PlaylistService wiring derivation", .serialized)
struct PlaylistServiceWiringTests {

    // MARK: - Derivation matrix

    @Test(
        "interval and liveUpdatesActive follow the caller's live-updates opt-in",
        .timeLimit(.minutes(1)),
        arguments: liveUpdatesDerivationCases
    )
    func derivesIntervalAndLiveUpdatesActive(_ testCase: LiveUpdatesDerivationCase) async throws {
        let fetcher = MockPlaylistFetcher()
        fetcher.playlistToReturn = .stub(playcuts: [.stub()])
        let source: MockLiveFsEventSource? = testCase.optedIn ? MockLiveFsEventSource() : nil

        let service = PlaylistService(
            fetcher: fetcher,
            cacheCoordinator: makeTestCacheCoordinator(),
            liveEventSource: source
        )

        let snapshot = await service.wiringSnapshot()
        #expect(snapshot.pollInterval == testCase.expectedInterval)
        #expect(snapshot.liveUpdatesActive == testCase.expectedLiveUpdatesActive)
    }

    // MARK: - Production-shape pin (AC #5)

    @Test(
        "PlaylistService with liveUpdatesEnabled left at its default stays poll-only",
        .timeLimit(.minutes(1))
    )
    func defaultInitStaysPollOnly() async throws {
        // Pins that watchOS/tvOS/widgets/intents — none of which pass
        // `liveUpdatesEnabled: true` — stay poll-only. With the version term
        // gone from the conjunction (#262), the caller's opt-in is the only
        // thing standing between those surfaces and a 300 s cadence, so this
        // guard carries more weight than it did, not less: a stray
        // `liveUpdatesActive = true` default would now make the watch up to
        // five minutes stale with nothing else to catch it.
        //
        // "Production-shaped" here is about leaving `liveUpdatesEnabled` at
        // its default, not about the cache: the coordinator is still injected,
        // since the default is the real on-disk `MigratingDiskCache` and this
        // suite is only `.serialized` within itself.
        let service = PlaylistService(
            cacheCoordinator: makeTestCacheCoordinator()
        )

        let snapshot = await service.wiringSnapshot()
        #expect(snapshot.liveUpdatesActive == false)
        #expect(snapshot.pollInterval == 30)
    }
}

// MARK: - Derivation matrix fixture

/// One row of the `optedIn -> (interval, liveUpdatesActive)` derivation
/// matrix. A named struct (rather than a raw tuple) so `@Test(arguments:)`
/// doesn't need to destructure a wide tuple — see the repo's Swift Testing
/// note about large tuple arrays blowing the type-checker.
struct LiveUpdatesDerivationCase: Sendable {
    let optedIn: Bool
    let expectedInterval: TimeInterval
    let expectedLiveUpdatesActive: Bool
}

/// Extracted to a top-level `let` with an explicit type annotation (per the
/// repo's Swift Testing tips) rather than inlined into `@Test(arguments:)`.
///
/// This was a `(version, optedIn)` matrix until #262. The rows that pinned v1
/// behaviour — that v1 wired in no SSE source even when the caller opted in,
/// and that `switchAPIVersion(to:)` re-derived fetcher, interval and
/// subscription together — are gone along with the enrichment-loss and
/// reentrancy tests that sat beside them. That is not coverage that lapsed:
/// there is one API version and nothing that switches between versions at
/// runtime, so the behaviour they pinned has no reachable code path left to
/// regress.
let liveUpdatesDerivationCases: [LiveUpdatesDerivationCase] = [
    // 30, NOT 300 — the watchOS/tvOS regression guard. Wiring an SSE source is
    // the caller's decision; nothing else may imply it.
    .init(optedIn: false, expectedInterval: 30, expectedLiveUpdatesActive: false),
    .init(optedIn: true, expectedInterval: 300, expectedLiveUpdatesActive: true),
]
