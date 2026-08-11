//
//  PlaycutSelectionTests.swift
//  WXYC
//
//  Guards the detail cover's zoom-source identity. `PlaycutSelection.transitionID`
//  (and the `Identifiable` id derived from it) must be distinct per row on both
//  surfaces the cover presents from. The Liked tab is the trap:
//  `LikedSongSnapshot.toPlaycut()` hardcodes `id: 0`, so keying the zoom on
//  `playcut.id` would collapse every liked row to source id 0 and the zoom
//  couldn't tell which row it animated out of.
//
//  Also guards #408: `PlaycutSelection` composes AppServices' `NowPlayingItem`
//  for its `{ playcut, artwork }` pair rather than re-declaring the two fields,
//  so the field mapping and the bridging initializer are pinned here.
//
//  Created by Jake Bromberg on 08/01/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppServices
import Foundation
import LikedSongs
import Playlist
import Testing
@testable import WXYC

@MainActor
@Suite("PlaycutSelection zoom identity")
struct PlaycutSelectionTests {
    private func playcut(id: UInt64, artist: String, title: String) -> Playcut {
        Playcut(
            id: id,
            hour: 0,
            chronOrderID: 0,
            timeCreated: 0,
            songTitle: title,
            labelName: nil,
            artistName: artist,
            releaseTitle: nil
        )
    }

    @Test("A flowsheet selection keys the zoom on the unique playcut id")
    func flowsheetSelectionKeysOnPlaycutID() {
        let selection = PlaycutSelection(
            playcut: playcut(id: 42, artist: "Juana Molina", title: "la paradoja"),
            artwork: nil
        )
        #expect(selection.transitionID == AnyHashable(UInt64(42)))
        #expect(selection.id == AnyHashable(UInt64(42)))
    }

    @Test("Distinct liked snapshots produce distinct zoom ids despite toPlaycut()'s id 0")
    func likedSnapshotsHaveDistinctZoomIDs() {
        let epoch = Date(timeIntervalSince1970: 0)
        let a = LikedSongSnapshot(
            playcut: playcut(id: 0, artist: "Juana Molina", title: "la paradoja"),
            likedAt: epoch
        )
        let b = LikedSongSnapshot(
            playcut: playcut(id: 0, artist: "Stereolab", title: "Miss Modular"),
            likedAt: epoch
        )

        // Precondition: the bridge synthesizes the sentinel id 0 for both, so the
        // playcut id can't distinguish them — the exact hazard this suite guards.
        #expect(a.toPlaycut().id == 0)
        #expect(b.toPlaycut().id == 0)

        let selA = PlaycutSelection(playcut: a.toPlaycut(), artwork: nil, transitionID: a.id)
        let selB = PlaycutSelection(playcut: b.toPlaycut(), artwork: nil, transitionID: b.id)

        // Keyed on the snapshot id the two are distinct, so `.fullScreenCover(item:)`
        // and the zoom source both resolve to the right row.
        #expect(selA.transitionID != selB.transitionID)
        #expect(selA.id != selB.id)
        #expect(selA != selB)
        #expect(selA.transitionID == AnyHashable(a.id))
    }

    @Test("Bridges from a NowPlayingItem, since it's the same {playcut, artwork} contract AppServices already declares")
    func bridgesFromNowPlayingItem() {
        let pc = playcut(id: 7, artist: "Stereolab", title: "Miss Modular")
        let item = NowPlayingItem(playcut: pc, artwork: nil)

        let selection = PlaycutSelection(item: item)

        // The pair forwards verbatim from the AppServices item — no separate
        // re-declared fields to drift out of sync with it.
        #expect(selection.playcut == item.playcut)
        #expect(selection.artwork == item.artwork)
        // The default transition id still keys on the playcut id, matching
        // the `init(playcut:artwork:transitionID:)` entry point's default.
        #expect(selection.transitionID == AnyHashable(pc.id))
    }

    @Test("The playcut/artwork initializer and the NowPlayingItem-bridging initializer agree")
    func playcutInitializerAgreesWithItemInitializer() {
        let pc = playcut(id: 9, artist: "Chuquimamani-Condori", title: "Call Your Name")

        let viaFields = PlaycutSelection(playcut: pc, artwork: nil, transitionID: "custom-key")
        let viaItem = PlaycutSelection(item: NowPlayingItem(playcut: pc, artwork: nil), transitionID: "custom-key")

        #expect(viaFields.playcut == viaItem.playcut)
        #expect(viaFields.artwork == viaItem.artwork)
        #expect(viaFields.transitionID == viaItem.transitionID)
        #expect(viaFields == viaItem)
    }
}
