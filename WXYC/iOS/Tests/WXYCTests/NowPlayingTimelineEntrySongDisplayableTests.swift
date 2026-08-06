//
//  NowPlayingTimelineEntrySongDisplayableTests.swift
//  WXYC
//
//  Guards `NowPlayingTimelineEntry`'s `SongDisplayable` conformance — the
//  bridge that lets the widget's `Header`/`Medium`/`Small` rows feed the
//  timeline entry straight into the shared `SongInfoColumn` text column
//  instead of hand-rolling their own title/artist `Text` stack (issue #771).
//
//  Created by Jake Bromberg on 08/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppServices
import Playlist
import Testing
import WidgetKit
@testable import WXYC

@Suite("NowPlayingTimelineEntry SongDisplayable bridge")
struct NowPlayingTimelineEntrySongDisplayableTests {
    private func playcut(artist: String, title: String) -> Playcut {
        Playcut(
            id: 1,
            hour: 0,
            chronOrderID: 0,
            timeCreated: 0,
            songTitle: title,
            labelName: nil,
            artistName: artist,
            releaseTitle: nil
        )
    }

    @Test("artistName mirrors the entry's artist")
    func artistNameMirrorsArtist() {
        let item = NowPlayingItem(playcut: playcut(artist: "Chuquimamani-Condori", title: "Call Your Name"))
        let entry = NowPlayingTimelineEntry(nowPlayingItem: item, recentItems: [], family: .systemSmall)
        #expect(entry.artistName == entry.artist)
        #expect(entry.artistName == "Chuquimamani-Condori")
    }

    @Test("songTitle is unchanged (the entry already declares it)")
    func songTitleUnchanged() {
        let item = NowPlayingItem(playcut: playcut(artist: "Juana Molina", title: "la paradoja"))
        let entry = NowPlayingTimelineEntry(nowPlayingItem: item, recentItems: [], family: .systemMedium)
        #expect(entry.songTitle == "la paradoja")
    }

    @Test("releaseTitle is always nil — the timeline entry carries no release field")
    func releaseTitleIsNil() {
        let item = NowPlayingItem(playcut: playcut(artist: "Stereolab", title: "Miss Modular"))
        let entry = NowPlayingTimelineEntry(nowPlayingItem: item, recentItems: [], family: .systemLarge)
        #expect(entry.releaseTitle == nil)
    }

    @Test("The empty-state entry still bridges its synthetic copy")
    func emptyStateBridges() {
        let entry = NowPlayingTimelineEntry.emptyState(family: .systemSmall)
        #expect(entry.artistName == "No Data Available")
        #expect(entry.songTitle == "Tune in to WXYC 89.3 FM")
    }
}
