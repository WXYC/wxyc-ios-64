//
//  WidgetStateServiceReloadTests.swift
//  AppServices
//
//  Tests for which widget reloads WidgetStateService actually issues: the
//  budget-exempt ones it should take while the audio session is live, and the
//  budgeted ones it must keep declining while the app is idle in the
//  background.
//
//  Created by Jake Bromberg on 08/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if canImport(WidgetKit)
import Caching
import Foundation
import PlaybackCore
import PlaylistTesting
import Testing
import WidgetKit
@testable import Playlist
@testable import AppServices

@MainActor
@Suite("WidgetStateService Reloads", .timeLimit(.minutes(1)))
struct WidgetStateServiceReloadTests {

    // MARK: - Playlist updates

    @Test("A flowsheet change reloads the widget while playback is active in the background")
    func playlistUpdateReloadsWhileBackgroundedAndPlaying() async throws {
        // The whole point of the exemption: WidgetKit does not charge reloads
        // against the daily budget while the app holds an active audio
        // session. A listener is exactly the user whose widget most needs to
        // track the flowsheet, so these reloads are free and should be taken.
        let harness = Harness()
        harness.playback.state = .playing
        harness.service.start()
        harness.service.setForegrounded(false)
        await harness.settle()

        let before = harness.reloader.callCount
        await harness.broadcastFlowsheetChange(songTitle: "Back, Baby")

        await harness.reloader.waitForCallCount(before + 1)
        #expect(harness.reloader.callCount > before)
    }

    @Test("A flowsheet change does not reload the widget while backgrounded and idle")
    func playlistUpdateDoesNotReloadWhileBackgroundedAndIdle() async throws {
        // Budgeted reloads are scarce (40-70/day). Spending one on a listener
        // who isn't listening and isn't looking is the behavior the decaying
        // timeline schedule replaces, so this path must stay closed.
        let harness = Harness()
        harness.playback.state = .idle
        harness.service.start()
        harness.service.setForegrounded(false)
        await harness.settle()

        let before = harness.reloader.callCount
        await harness.broadcastFlowsheetChange(songTitle: "Call Your Name")
        await harness.settle()

        #expect(harness.reloader.callCount == before)

        // Non-vacuity: the same kind of broadcast must reach the reloader once
        // the gate opens, proving the silence above was the gate and not a
        // pipeline that never delivered anything in the first place.
        harness.service.setForegrounded(true)
        let afterForeground = harness.reloader.callCount
        await harness.broadcastFlowsheetChange(songTitle: "In a Sentimental Mood")

        await harness.reloader.waitForCallCount(afterForeground + 1)
        #expect(harness.reloader.callCount > afterForeground)
    }

    // MARK: - Playback transitions

    @Test("Playback becoming active reloads the widget even when backgrounded")
    func playbackStartReloadsWhileBackgrounded() async throws {
        // The transition into `.playing` is itself the moment the audio
        // session opens, so this reload is exempt too — and it is what swaps
        // the widget's play glyph for a pause glyph.
        let harness = Harness()
        harness.service.start()
        harness.service.setForegrounded(false)
        await harness.settle()

        let before = harness.reloader.callCount
        harness.playback.state = .playing

        await harness.reloader.waitForCallCount(before + 1)
        #expect(harness.reloader.callCount > before)
    }

    // MARK: - Engagement recording

    @Test("Foregrounding records an engagement timestamp")
    func foregroundingRecordsEngagement() async throws {
        let harness = Harness()
        #expect(harness.engagement.lastEngagement == nil)

        harness.service.setForegrounded(true)

        #expect(harness.engagement.lastEngagement != nil)
    }

    @Test("Starting playback records an engagement timestamp")
    func playbackStartRecordsEngagement() async throws {
        let harness = Harness()
        harness.service.start()
        await harness.settle()
        #expect(harness.engagement.lastEngagement == nil)

        harness.playback.state = .playing

        await harness.waitForEngagement()
        #expect(harness.engagement.lastEngagement != nil)
    }

    @Test("Stopping playback does not stamp a fresh engagement")
    func playbackStopDoesNotRecordEngagement() async throws {
        // Engagement means the user did something. A stream ending — or the
        // app being torn down — is not an act of interest, and stamping it
        // would hold the widget in the hot tier for 30 minutes after the user
        // walked away.
        let harness = Harness()
        harness.playback.state = .playing
        harness.service.start()

        await harness.waitForEngagement()
        let stamped = try #require(harness.engagement.lastEngagement)

        harness.playback.state = .idle
        await harness.settle()

        #expect(harness.engagement.lastEngagement == stamped)
    }
}

// MARK: - Harness

/// Bundles the service with the doubles the tests assert against, so each test
/// reads as its scenario rather than five lines of wiring.
@MainActor
private final class Harness {
    let reloader = MockWidgetReloader()
    let playback = MockPlaybackController()
    let engagement: WidgetEngagementStore
    let fetcher = MockPlaylistFetcher()
    let playlistService: PlaylistService
    let service: WidgetStateService

    init() {
        // A per-harness `InMemoryDefaults`, never `UserDefaults.wxyc`: that
        // suite is a process-global app group shared with every other test
        // target, and an engagement stamp leaking out of here would quietly
        // change another suite's tier.
        engagement = WidgetEngagementStore(storage: InMemoryDefaults())
        playlistService = PlaylistService(
            fetcher: fetcher,
            interval: 60,
            cacheCoordinator: CacheCoordinator(cache: InMemoryCache())
        )
        service = WidgetStateService(
            playbackController: playback,
            playlistService: playlistService,
            relevanceUpdater: MockWidgetRelevanceUpdater(),
            reloader: reloader,
            engagementStore: engagement
        )
    }

    /// Pushes a new flowsheet through the service so subscribers see an update.
    ///
    /// The playcut has to differ from the last one and the playlist has to
    /// carry content: `PlaylistService.ingest(_:)` drops a content-empty
    /// payload without broadcasting, so a test that fetched the default
    /// `.empty` stub would be asserting against the yield every new subscriber
    /// gets on subscription rather than against a real update.
    func broadcastFlowsheetChange(songTitle: String) async {
        let id = UInt64(abs(songTitle.hashValue % 100_000) + 1)
        fetcher.playlistToReturn = .stub(playcuts: [.stub(id: id, songTitle: songTitle)])
        _ = await playlistService.fetchAndCachePlaylist()
    }

    /// Yields until an engagement has been stamped.
    ///
    /// Engagement and reloads are written by the same observation, but not
    /// atomically — waiting on the reload counter to stand in for the stamp
    /// races the two.
    func waitForEngagement() async {
        while engagement.lastEngagement == nil {
            await Task.yield()
        }
    }

    /// Yields enough times for any already-scheduled observation delivery to run.
    ///
    /// Only ever used to give a reload the chance to arrive *before* asserting
    /// it did not, and to drain the baseline yield every new `updates()`
    /// subscriber receives. Every positive assertion polls instead, so no
    /// test's success depends on this bound being generous enough.
    func settle() async {
        for _ in 0..<50 {
            await Task.yield()
        }
    }
}

// MARK: - Mock Types

@MainActor
final class MockWidgetReloader: WidgetReloading {
    private(set) var callCount = 0

    func reloadAllTimelines() {
        callCount += 1
    }

    /// Yields the main actor until at least `count` reloads have been recorded.
    func waitForCallCount(_ count: Int) async {
        while callCount < count {
            await Task.yield()
        }
    }
}
#endif
