//
//  PlaylistOnAirTests.swift
//  Playlist
//
//  Verifies the "on air" promotion: the current DJ's sign-on is surfaced via
//  Playlist.onAirSignOn and removed from Playlist.timelineEntries so it can be
//  rendered as a dedicated banner instead of inline.
//
//  Created by Jake Bromberg on 06/18/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Playlist

@Suite("Playlist On Air Tests")
struct PlaylistOnAirTests {

    @Test("onAirSignOn returns the latest marker when it is a sign-on")
    func onAirSignOnReturnsLatestSignOn() {
        let playlist = Playlist.stub(
            playcuts: [.stub(id: 1, chronOrderID: 1)],
            showMarkers: [.stub(id: 2, chronOrderID: 5, isStart: true, djName: "HOUNDSTOOTH")]
        )

        #expect(playlist.onAirSignOn?.id == 2)
        #expect(playlist.onAirSignOn?.djName == "HOUNDSTOOTH")
    }

    @Test("onAirSignOn is nil when the latest marker is a sign-off")
    func onAirSignOnNilWhenLatestIsSignOff() {
        let playlist = Playlist.stub(
            showMarkers: [
                .stub(id: 1, chronOrderID: 1, isStart: true, djName: "HOUNDSTOOTH"),
                .stub(id: 2, chronOrderID: 2, isStart: false, djName: "HOUNDSTOOTH"),
            ]
        )

        #expect(playlist.onAirSignOn == nil)
    }

    @Test("onAirSignOn is nil when there are no show markers")
    func onAirSignOnNilWithoutMarkers() {
        let playlist = Playlist.stub(playcuts: [.stub(id: 1)])

        #expect(playlist.onAirSignOn == nil)
    }

    @Test("onAirSignOn ignores an older sign-on when a newer sign-off exists")
    func onAirSignOnIgnoresOlderSignOn() {
        let playlist = Playlist.stub(
            showMarkers: [
                .stub(id: 10, chronOrderID: 10, isStart: true, djName: "OLD DJ"),
                .stub(id: 11, chronOrderID: 11, isStart: false, djName: "OLD DJ"),
            ]
        )

        #expect(playlist.onAirSignOn == nil)
    }

    @Test("timelineEntries excludes exactly the on-air sign-on marker")
    func timelineEntriesExcludesOnAirSignOn() {
        let onAir = ShowMarker.stub(id: 99, chronOrderID: 99, isStart: true, djName: "HOUNDSTOOTH")
        let playlist = Playlist.stub(
            playcuts: [.stub(id: 1, chronOrderID: 1)],
            showMarkers: [onAir]
        )

        let ids = playlist.timelineEntries.map(\.id)
        #expect(!ids.contains(onAir.id))
        #expect(ids.contains(1))
    }

    @Test("timelineEntries drops sign-offs and the on-air sign-on, keeps other sign-ons and entries")
    func timelineEntriesDropsSignOffsAndOnAir() {
        let onAir = ShowMarker.stub(id: 50, chronOrderID: 50, isStart: true, djName: "CURRENT")
        let previousSignOff = ShowMarker.stub(id: 40, chronOrderID: 40, isStart: false, djName: "PREVIOUS")
        let previousSignOn = ShowMarker.stub(id: 30, chronOrderID: 30, isStart: true, djName: "PREVIOUS")
        let playlist = Playlist.stub(
            playcuts: [.stub(id: 1, chronOrderID: 1)],
            breakpoints: [.stub(id: 2, chronOrderID: 2)],
            talksets: [.stub(id: 3, chronOrderID: 3)],
            showMarkers: [onAir, previousSignOff, previousSignOn]
        )

        let ids = playlist.timelineEntries.map(\.id)
        #expect(!ids.contains(onAir.id))            // current DJ lives in the banner
        #expect(!ids.contains(previousSignOff.id))  // sign-offs are hidden entirely
        #expect(ids.contains(previousSignOn.id))    // earlier sign-ons remain as show boundaries
        #expect(ids.contains(1))
        #expect(ids.contains(2))
        #expect(ids.contains(3))
    }

    @Test("timelineEntries drops sign-offs even when no one is on the air")
    func timelineEntriesDropsSignOffsWithoutOnAir() {
        let signOff = ShowMarker.stub(id: 2, chronOrderID: 2, isStart: false, djName: "PREVIOUS")
        let playlist = Playlist.stub(
            playcuts: [.stub(id: 1, chronOrderID: 1)],
            showMarkers: [signOff]
        )

        let ids = playlist.timelineEntries.map(\.id)
        #expect(!ids.contains(signOff.id))
        #expect(ids.contains(1))
    }

    @Test("onAirTitle is the DJ name when present")
    func onAirTitleWithName() {
        let marker = ShowMarker.stub(isStart: true, djName: "HOUNDSTOOTH")
        #expect(marker.onAirTitle == "HOUNDSTOOTH")
    }

    @Test("onAirTitle falls back to the station name when the DJ name is nil")
    func onAirTitleWithoutName() {
        let marker = ShowMarker.stub(isStart: true, djName: nil)
        #expect(marker.onAirTitle == "WXYC")
    }
}
