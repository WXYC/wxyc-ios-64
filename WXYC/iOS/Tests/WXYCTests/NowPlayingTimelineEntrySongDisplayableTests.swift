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

    @Test("The station-line entry leads with the station line, not the empty-state text")
    func stationLineLeads() {
        let entry = NowPlayingTimelineEntry.stationLine(recentItems: [], family: .systemLarge)
        #expect(entry.artistName == "Tune in to WXYC 89.3 FM")
        #expect(entry.songTitle.isEmpty)
    }

    @Test("The who's-on entry leads with the table's title and artist, and the station artwork")
    func whosOnLeads() {
        let spotlight = NowPlayingSpotlight(title: "Backyard BBQ", artist: "Weirs", album: "WXYC 89.3 FM", artwork: .station)
        let entry = NowPlayingTimelineEntry.whosOn(spotlight, recentItems: [], family: .systemLarge)
        #expect(entry.songTitle == "Backyard BBQ")
        #expect(entry.artistName == "Weirs")
        #expect(entry.artwork == nil)
    }
}

@Suite("NowPlayingTimelineEntry specialty program entries")
struct NowPlayingTimelineEntryProgramTests {
    private let program = SpecialtyShowRef(id: 3, slug: "hogwash", name: "Hogwash", shortName: "HW", tagline: "Weird and wonderful")
    private var headline: NowPlayingHeadline { NowPlayingHeadline(program: program, person: "DJ Hog") }

    private func recents(_ count: Int) -> [NowPlayingItem] {
        (0..<count).map { id in
            NowPlayingItem(playcut: Playcut(
                id: UInt64(id), hour: 0, chronOrderID: UInt64(id), timeCreated: 0,
                songTitle: "Song \(id)", labelName: nil, artistName: "Artist \(id)", releaseTitle: nil
            ))
        }
    }

    @Test("The headline entry names the program over the person and leads with the program")
    func headlineEntry() {
        let entry = NowPlayingTimelineEntry(headline: headline, logo: nil, recentItems: [], family: .systemSmall)
        #expect(entry.artist == "Hogwash")
        #expect(entry.songTitle == "DJ Hog")
        #expect(entry.headline?.tagline == "Weird and wonderful")
        #expect(entry.programLeads)
        #expect(entry.artwork == nil)
    }

    @Test("A specialty show's entries drop to two recents; a song outside a program keeps all it is given", arguments: [WidgetFamily.systemSmall, .systemMedium])
    func rowCounts(family: WidgetFamily) {
        let item = NowPlayingItem(playcut: recents(1)[0].playcut)
        let program = NowPlayingTimelineEntry(headline: headline, logo: nil, recentItems: recents(3), family: family)
        let song = NowPlayingTimelineEntry(nowPlayingItem: item, recentItems: recents(3), family: family, headline: headline)
        let freeform = NowPlayingTimelineEntry(nowPlayingItem: item, recentItems: recents(3), family: family)
        #expect(program.recentItems.count == 2)
        #expect(song.recentItems.count == 2)
        #expect(!song.programLeads)
        #expect(freeform.recentItems.count == 3)
        #expect(freeform.headline == nil)
    }
}
