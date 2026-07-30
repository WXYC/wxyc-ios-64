//
//  TourAlertCoordinatorTests.swift
//  AppServices
//
//  Verifies the integration seam that pumps on-air playcuts into the tour-alert
//  planner and forwards a decision to a `TourAlertScheduling`: it posts once for
//  a fresh on-tour play, de-dups a show already alerted this session, and posts
//  nothing while the stream is paused.
//
//  Created by Jake Bromberg on 07/30/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if !os(watchOS) && !os(tvOS)
import Concerts
import ConcertsTesting
import Foundation
import Playlist
import PlaylistTesting
import Testing
@testable import AppServices

@Suite("TourAlertCoordinator")
@MainActor
struct TourAlertCoordinatorTests {

    /// Records every posted alert so a test can assert the count and payload.
    private actor RecordingScheduler: TourAlertScheduling {
        private(set) var posted: [TourAlert] = []
        func post(_ alert: TourAlert) async {
            posted.append(alert)
        }
    }

    private func onTourPlaycut(artistName: String = "Jessica Pratt", concertID: Int = 4821) -> Playcut {
        Playcut.stub(
            artistName: artistName,
            upcomingShow: Concert.stub(id: concertID, headliningArtistRaw: artistName)
        )
    }

    @Test("posts once for a fresh on-tour play while playing")
    func postsOnceWhenPlaying() async {
        let scheduler = RecordingScheduler()
        let coordinator = TourAlertCoordinator(scheduler: scheduler)

        await coordinator.ingest(playcut: onTourPlaycut(concertID: 4821), isPlaying: true)

        let posted = await scheduler.posted
        #expect(posted.count == 1)
        #expect(posted.first?.concertID == 4821)
    }

    @Test("de-dups a show already alerted this session")
    func dedupsRepeatedShow() async {
        let scheduler = RecordingScheduler()
        let coordinator = TourAlertCoordinator(scheduler: scheduler)

        await coordinator.ingest(playcut: onTourPlaycut(concertID: 4821), isPlaying: true)
        // Same show still on air on the next poll tick.
        await coordinator.ingest(playcut: onTourPlaycut(concertID: 4821), isPlaying: true)

        let posted = await scheduler.posted
        #expect(posted.count == 1)
    }

    @Test("posts again for a different show")
    func postsForDifferentShow() async {
        let scheduler = RecordingScheduler()
        let coordinator = TourAlertCoordinator(scheduler: scheduler)

        await coordinator.ingest(playcut: onTourPlaycut(concertID: 4821), isPlaying: true)
        await coordinator.ingest(playcut: onTourPlaycut(concertID: 9001), isPlaying: true)

        let posted = await scheduler.posted
        #expect(posted.count == 2)
        #expect(Set(posted.map(\.concertID)) == [4821, 9001])
    }

    @Test("posts nothing while the stream is paused")
    func silentWhilePaused() async {
        let scheduler = RecordingScheduler()
        let coordinator = TourAlertCoordinator(scheduler: scheduler)

        await coordinator.ingest(playcut: onTourPlaycut(), isPlaying: false)

        let posted = await scheduler.posted
        #expect(posted.isEmpty)
    }

    @Test("uses the injected resolver, so a mocked show alerts even with no embedded show")
    func honorsInjectedResolver() async {
        // Mirrors the DEBUG "Mock ticket on first item" wiring: a playcut with no
        // embedded `upcomingShow`, but the injected resolver fabricates one.
        let scheduler = RecordingScheduler()
        let mockShow = Concert.stub(id: 7777)
        let coordinator = TourAlertCoordinator(
            scheduler: scheduler,
            resolveUpcomingShow: { _ in mockShow }
        )

        await coordinator.ingest(
            playcut: Playcut.stub(artistName: "Juana Molina", upcomingShow: nil),
            isPlaying: true
        )

        let posted = await scheduler.posted
        #expect(posted.count == 1)
        #expect(posted.first?.concertID == 7777)
    }
}
#endif
