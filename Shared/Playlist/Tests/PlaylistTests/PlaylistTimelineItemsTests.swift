//
//  PlaylistTimelineItemsTests.swift
//  Playlist
//
//  Verifies Playlist.timelineItems: the coalescing pass that folds the sorted
//  timeline into render-ready items, collapsing each maximal run of adjacent
//  talksets and breakpoints into a single seam (at most one between two songs).
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Playlist

@Suite("Playlist Timeline Items Tests")
struct PlaylistTimelineItemsTests {

    // MARK: - Lone seams

    @Test("A lone talkset becomes one mic-break seam with no hour")
    func loneTalkset() {
        let playlist = Playlist.stub(
            playcuts: [.stub(id: 5, chronOrderID: 5), .stub(id: 2, chronOrderID: 2)],
            talksets: [.stub(id: 4, chronOrderID: 4)]
        )

        let seams = playlist.timelineItems.compactMap(\.asSeam)
        #expect(seams.count == 1)
        #expect(seams.first?.hasMicBreak == true)
        #expect(seams.first?.breakpoint == nil)
    }

    @Test("A lone breakpoint becomes one hour seam with no mic break")
    func loneBreakpoint() {
        let playlist = Playlist.stub(
            playcuts: [.stub(id: 5, chronOrderID: 5), .stub(id: 2, chronOrderID: 2)],
            breakpoints: [.stub(id: 4, chronOrderID: 4)]
        )

        let seams = playlist.timelineItems.compactMap(\.asSeam)
        #expect(seams.count == 1)
        #expect(seams.first?.hasMicBreak == false)
        #expect(seams.first?.breakpoint?.id == 4)
    }

    // MARK: - Coalescing adjacent markers

    @Test("Adjacent talkset + breakpoint coalesce into one seam carrying both")
    func adjacentTalksetAndBreakpoint() {
        let playlist = Playlist.stub(
            playcuts: [.stub(id: 5, chronOrderID: 5), .stub(id: 2, chronOrderID: 2)],
            breakpoints: [.stub(id: 3, chronOrderID: 3)],
            talksets: [.stub(id: 4, chronOrderID: 4)]
        )

        let seams = playlist.timelineItems.compactMap(\.asSeam)
        #expect(seams.count == 1)
        #expect(seams.first?.hasMicBreak == true)
        #expect(seams.first?.breakpoint?.id == 3)
    }

    @Test("Two adjacent talksets collapse to a single mic-break seam")
    func doubledTalkset() {
        let playlist = Playlist.stub(
            playcuts: [.stub(id: 5, chronOrderID: 5), .stub(id: 2, chronOrderID: 2)],
            talksets: [.stub(id: 4, chronOrderID: 4), .stub(id: 3, chronOrderID: 3)]
        )

        let seams = playlist.timelineItems.compactMap(\.asSeam)
        #expect(seams.count == 1)
        #expect(seams.first?.hasMicBreak == true)
    }

    @Test("A multi-hour breakpoint run collapses to one seam anchored to the newest hour")
    func multiHourBreakpointRun() {
        // Four adjacent breakpoints (no song between). Newest = highest chronOrderID.
        let playlist = Playlist.stub(
            playcuts: [.stub(id: 10, chronOrderID: 10), .stub(id: 1, chronOrderID: 1)],
            breakpoints: [
                .stub(id: 5, hour: 4000, chronOrderID: 5),
                .stub(id: 4, hour: 3000, chronOrderID: 4),
                .stub(id: 3, hour: 2000, chronOrderID: 3),
                .stub(id: 2, hour: 1000, chronOrderID: 2),
            ]
        )

        let seams = playlist.timelineItems.compactMap(\.asSeam)
        #expect(seams.count == 1)
        #expect(seams.first?.hasMicBreak == false)
        #expect(seams.first?.breakpoint?.id == 5)      // newest of the run
        #expect(seams.first?.breakpoint?.hour == 4000)
    }

    // MARK: - Non-adjacency keeps seams separate

    @Test("A talkset and a breakpoint separated by a song stay two seams")
    func nonAdjacentMarkersStaySeparate() {
        // Sorted desc: A(5), talkset(4), B(3), breakpoint(2), C(1)
        let playlist = Playlist.stub(
            playcuts: [.stub(id: 5, chronOrderID: 5), .stub(id: 3, chronOrderID: 3), .stub(id: 1, chronOrderID: 1)],
            breakpoints: [.stub(id: 2, chronOrderID: 2)],
            talksets: [.stub(id: 4, chronOrderID: 4)]
        )

        let seams = playlist.timelineItems.compactMap(\.asSeam)
        #expect(seams.count == 2)
        // Newest-first: the talkset seam leads, the hour seam follows.
        #expect(seams.first?.hasMicBreak == true)
        #expect(seams.first?.breakpoint == nil)
        #expect(seams.last?.hasMicBreak == false)
        #expect(seams.last?.breakpoint?.id == 2)
    }

    // MARK: - Other entry types

    @Test("Playcuts pass through as playcut items, newest first")
    func playcutsPassThrough() {
        let playlist = Playlist.stub(
            playcuts: [.stub(id: 3, chronOrderID: 3), .stub(id: 1, chronOrderID: 1)]
        )

        let playcutIDs = playlist.timelineItems.compactMap { $0.asPlaycut?.id }
        #expect(playcutIDs == [3, 1])
    }

    @Test("An earlier sign-on breaks a run and is not folded into a seam")
    func signOnBreaksRun() {
        // The current DJ's sign-on (id 10) is the latest marker, so it's promoted
        // to the banner and dropped from the timeline. An earlier sign-on (id 6)
        // is a real show boundary that survives and splits the surrounding markers.
        // Surviving timeline, newest-first: talkset(8), sign-on(6), breakpoint(4), song(1)
        let onAir = ShowMarker.stub(id: 10, chronOrderID: 10, isStart: true, djName: "CURRENT")
        let previousSignOn = ShowMarker.stub(id: 6, chronOrderID: 6, isStart: true, djName: "PREVIOUS")
        let playlist = Playlist.stub(
            playcuts: [.stub(id: 1, chronOrderID: 1)],
            breakpoints: [.stub(id: 4, chronOrderID: 4)],
            talksets: [.stub(id: 8, chronOrderID: 8)],
            showMarkers: [onAir, previousSignOn]
        )

        let items = playlist.timelineItems
        // The earlier sign-on survives as its own item, not merged into a seam.
        #expect(items.contains { $0.asShowMarker?.id == 6 })
        // Talkset and breakpoint sit on opposite sides of it, so two seams.
        let seams = items.compactMap(\.asSeam)
        #expect(seams.count == 2)
    }

    // MARK: - Reorder across a seam boundary (#839)

    @Test("A talkset that moves across a playcut boundary re-coalesces into the new seam, not the old one")
    func talksetReorderMovesAcrossPlaycutBoundary() {
        func kind(_ item: TimelineItem) -> String {
            switch item {
            case .playcut: "playcut"
            case .seam: "seam"
            case .showMarker: "marker"
            }
        }

        // Before a dj-site reorder: playcut A, talkset, playcut B, playcut C
        // (newest first) — the talkset sits between A and B.
        let playcutA = Playcut.stub(id: 1, chronOrderID: 40)
        let playcutB = Playcut.stub(id: 2, chronOrderID: 20)
        let playcutC = Playcut.stub(id: 3, chronOrderID: 10)
        let talksetBefore = Talkset.stub(id: 4, chronOrderID: 30)

        let before = Playlist.stub(playcuts: [playcutA, playcutB, playcutC], talksets: [talksetBefore])
        let beforeItems = before.timelineItems
        #expect(beforeItems.map(kind) == ["playcut", "seam", "playcut", "playcut"])

        // The DJ drags the talkset down past B on dj-site: its play_order
        // (and therefore its packed chronOrderID) drops below B's, so it now
        // sits between B and C instead.
        let talksetAfter = Talkset.stub(id: 4, chronOrderID: 15)
        let after = Playlist.stub(playcuts: [playcutA, playcutB, playcutC], talksets: [talksetAfter])
        let afterItems = after.timelineItems
        #expect(afterItems.map(kind) == ["playcut", "playcut", "seam", "playcut"])

        // The seam is anchored to the talkset's own id, so the reorder
        // relabels which two playcuts it sits between without needing new
        // coalescing logic.
        let afterSeam = afterItems.compactMap(\.asSeam).first
        #expect(afterSeam?.id == 4)
        #expect(afterSeam?.hasMicBreak == true)
    }

    // MARK: - Identity

    @Test("Each timeline item exposes a stable identity")
    func stableIdentity() {
        let playlist = Playlist.stub(
            playcuts: [.stub(id: 9, chronOrderID: 9)],
            talksets: [.stub(id: 8, chronOrderID: 8)]
        )

        let ids = playlist.timelineItems.map(\.id)
        #expect(ids.contains(9))    // the playcut
        #expect(ids.contains(8))    // the seam, anchored to its newest entry
        #expect(Set(ids).count == ids.count)   // no collisions
    }

    // MARK: - Plain label (watchOS / CarPlay / VoiceOver)

    @Test("plainLabel for a lone mic break is 'Mic break'")
    func plainLabelMicOnly() {
        let seam = Seam(id: 1, hasMicBreak: true, breakpoint: nil)
        #expect(seam.plainLabel == "Mic break")
    }

    @Test("plainLabel for a mic break with an hour leads with 'Mic break, '")
    func plainLabelMicAndHour() {
        let seam = Seam(id: 1, hasMicBreak: true, breakpoint: .stub(id: 2))
        #expect(seam.plainLabel.hasPrefix("Mic break, "))
    }

    @Test("plainLabel for an hour-only seam is just the hour label")
    func plainLabelHourOnly() {
        let breakpoint = Breakpoint.stub(id: 2)
        let seam = Seam(id: 1, hasMicBreak: false, breakpoint: breakpoint)
        #expect(seam.plainLabel == breakpoint.formattedDate)
        #expect(!seam.plainLabel.isEmpty)
    }
}

// Test-only pattern-match helpers.
private extension TimelineItem {
    var asSeam: Seam? { if case .seam(let s) = self { return s } else { return nil } }
    var asPlaycut: Playcut? { if case .playcut(let p) = self { return p } else { return nil } }
    var asShowMarker: ShowMarker? { if case .showMarker(let m) = self { return m } else { return nil } }
}
