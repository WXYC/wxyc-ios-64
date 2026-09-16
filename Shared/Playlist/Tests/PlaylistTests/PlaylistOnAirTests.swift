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

    @Test("onAirSignOn clears on a sign-off whose play_order is 0, even though it keys below its own sign-on")
    func onAirSignOnClearsOnPlayOrderZeroSignOff() {
        // The webhook path writes `sequenceWithinShow ?? 0`, so a sign-off can
        // carry play_order 0 and pack to `(show << 32) | 0` — BELOW its own
        // show's sign-on at `| 1`. Who is on the air is a question about the
        // marker log's event order, which is the insertion serial `id`, not
        // the display key: ranked by the composite, the departed DJ would
        // stay promoted on the banner indefinitely.
        let playlist = Playlist.stub(
            showMarkers: [
                .stub(id: 20, chronOrderID: UInt64(42) << 32 | 1, isStart: true, djName: "HOUNDSTOOTH"),
                .stub(id: 21, chronOrderID: UInt64(42) << 32 | 0, isStart: false, djName: "HOUNDSTOOTH"),
            ]
        )

        #expect(playlist.onAirSignOn == nil)
    }

    @Test("onAirSignOn promotes a NULL-show_id sign-on that postdates a packed sign-off")
    func onAirSignOnPromotesBareKeyedSignOn() {
        // A sign-on with no show_id takes the bare-id fallback key, below
        // every packed marker — under the display key the DJ actually on the
        // air would lose `max()` to the previous show's sign-off and vanish
        // from the banner. Event order is id order.
        let playlist = Playlist.stub(
            showMarkers: [
                .stub(id: 8, chronOrderID: UInt64(41) << 32 | 1, isStart: true, djName: "PREVIOUS"),
                .stub(id: 9, chronOrderID: UInt64(41) << 32 | 2, isStart: false, djName: "PREVIOUS"),
                .stub(id: 12, chronOrderID: 12, isStart: true, djName: "CURRENT"),
            ]
        )

        #expect(playlist.onAirSignOn?.djName == "CURRENT")
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

    @Test("timelineEntries drops only the on-air sign-on, keeping both boundaries of a past show")
    func timelineEntriesKeepsPastShowBoundaries() {
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
        #expect(!ids.contains(onAir.id))           // current DJ lives in the banner
        #expect(ids.contains(previousSignOff.id))  // the handoff off the air is the show's top boundary
        #expect(ids.contains(previousSignOn.id))   // and its sign-on is the bottom one
        #expect(ids.contains(1))
        #expect(ids.contains(2))
        #expect(ids.contains(3))
    }

    @Test("timelineEntries keeps a sign-off when no one is on the air")
    func timelineEntriesKeepsSignOffWithoutOnAir() {
        let signOff = ShowMarker.stub(id: 2, chronOrderID: 2, isStart: false, djName: "PREVIOUS")
        let playlist = Playlist.stub(
            playcuts: [.stub(id: 1, chronOrderID: 1)],
            showMarkers: [signOff]
        )

        let ids = playlist.timelineEntries.map(\.id)
        #expect(ids.contains(signOff.id))
        #expect(ids.contains(1))
    }

    /// A sign-off sorts above its own show's content, so it heads the block it
    /// closes rather than trailing it: Backend stamps the marker with the show's
    /// last `play_order`, which the packed `(show_id, play_order)` key carries
    /// into the newest-first display order. Sampled over 108 consecutive shows,
    /// 104 put the sign-off at the show's maximum `play_order`; the other four
    /// had a handful of rows logged after the DJ signed off, which the feed then
    /// shows above the marker — the flowsheet as logged, not a mis-sort.
    @Test("A show's sign-off heads its block and its sign-on closes it")
    func signOffHeadsTheShowItCloses() {
        // show 7, play_order 1...3 — packed key is show << 32 | play_order.
        let key: (UInt64, UInt64) -> UInt64 = { show, order in (show << 32) | order }
        let signOn = ShowMarker.stub(id: 10, chronOrderID: key(7, 1), isStart: true, djName: "PREVIOUS")
        let song = Playcut.stub(id: 11, chronOrderID: key(7, 2))
        let signOff = ShowMarker.stub(id: 12, chronOrderID: key(7, 3), isStart: false, djName: "PREVIOUS")
        let playlist = Playlist.stub(playcuts: [song], showMarkers: [signOn, signOff])

        #expect(playlist.timelineEntries.map(\.id) == [signOff.id, song.id, signOn.id])
    }

    @Test(
        "timelineLabel names the DJ and the direction, and stays subjectless without a name",
        arguments: [
            (String?("DJ Moo"), true, "DJ Moo signed on"),
            (String?("DJ Moo"), false, "DJ Moo signed off"),
            // An empty dj_name reaches the model as nil (FlowsheetEntryType
            // folds it), and must not borrow onAirTitle's "WXYC" fallback —
            // "WXYC signed off" would assert the station left the air.
            (String?.none, true, "Signed on"),
            (String?.none, false, "Signed off"),
        ]
    )
    func timelineLabelCopy(djName: String?, isStart: Bool, expected: String) {
        #expect(ShowMarker.stub(isStart: isStart, djName: djName).timelineLabel == expected)
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
