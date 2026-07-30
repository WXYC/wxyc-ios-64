//
//  TourAlertPlannerTests.swift
//  AppServices
//
//  Exercises the pure decision + copy for the dev-only "artist on tour"
//  lock-screen alert: an alert fires only while the stream is playing, the
//  on-air playcut carries an `upcomingShow`, and that show hasn't already been
//  alerted this session; and the body's day label is pinned to the station zone
//  (so it can't render the previous day west of Eastern).
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

@Suite("TourAlertPlanner")
struct TourAlertPlannerTests {

    private func playcut(artistName: String = "Jessica Pratt") -> Playcut {
        Playcut.stub(artistName: artistName)
    }

    private func show(
        concertID: Int = 4821,
        venueName: String = "Cat's Cradle",
        city: String = "Carrboro",
        startsOn: Date = Concert.defaultStartsOn
    ) -> Concert {
        Concert.stub(
            id: concertID,
            venue: .stub(name: venueName, city: city),
            startsOn: startsOn,
            headliningArtistRaw: "Jessica Pratt"
        )
    }

    @Test("no alert when the stream is not playing")
    func silentWhenNotPlaying() {
        let alert = TourAlertPlanner.plan(
            isPlaying: false,
            playcut: playcut(),
            upcomingShow: show(),
            alreadyNotified: []
        )
        #expect(alert == nil)
    }

    @Test("no alert when there is no on-air playcut")
    func silentWhenNoPlaycut() {
        let alert = TourAlertPlanner.plan(
            isPlaying: true,
            playcut: nil,
            upcomingShow: show(),
            alreadyNotified: []
        )
        #expect(alert == nil)
    }

    @Test("no alert when the on-air artist has no upcoming show")
    func silentWhenNoUpcomingShow() {
        let alert = TourAlertPlanner.plan(
            isPlaying: true,
            playcut: playcut(artistName: "Juana Molina"),
            upcomingShow: nil,
            alreadyNotified: []
        )
        #expect(alert == nil)
    }

    @Test("no alert when the show was already notified this session")
    func silentWhenAlreadyNotified() {
        let alert = TourAlertPlanner.plan(
            isPlaying: true,
            playcut: playcut(),
            upcomingShow: show(concertID: 4821),
            alreadyNotified: [4821]
        )
        #expect(alert == nil)
    }

    @Test("fires with the on-air artist, concert id, and venue/city/date in the body")
    func firesWithContent() throws {
        let alert = try #require(
            TourAlertPlanner.plan(
                isPlaying: true,
                playcut: playcut(artistName: "Jessica Pratt"),
                upcomingShow: show(concertID: 4821, venueName: "Cat's Cradle", city: "Carrboro"),
                alreadyNotified: []
            )
        )

        #expect(alert.concertID == 4821)
        #expect(alert.artistName == "Jessica Pratt")
        #expect(alert.title == "Jessica Pratt is on tour")
        #expect(alert.body.contains("Cat's Cradle"))
        #expect(alert.body.contains("Carrboro"))
    }

    @Test("the body's day label is rendered in the station zone, not the device zone")
    func dayLabelUsesStationZone() throws {
        // 2026-08-01 at midnight US Eastern. A device in Los Angeles reading this
        // instant in its own zone would land on 2026-07-31 — the off-by-one the
        // station formatter guards against.
        let startsOn = Concert.defaultStartsOn
        let alert = try #require(
            TourAlertPlanner.plan(
                isPlaying: true,
                playcut: playcut(),
                upcomingShow: show(startsOn: startsOn),
                alreadyNotified: []
            )
        )

        // Expected day built with the same station contract, independently of
        // the planner, so the assertion can't pass by construction.
        let expectedDay = DateFormatter.station("EEE, MMM d").string(from: startsOn)
        #expect(alert.body.contains(expectedDay))
    }
}
#endif
