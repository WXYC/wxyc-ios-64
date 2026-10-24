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

    @Test("A freeform who's-on entry puts the role line on the bold line over the DJ handle, with no artwork", arguments: [WidgetFamily.systemSmall, .systemMedium, .systemLarge])
    func whosOnLeads(family: WidgetFamily) {
        let spotlight = NowPlayingSpotlight(title: "In the studio: Ana Lucía Ríos", artist: "DJ Sidechain", album: "WXYC 89.3 FM", artwork: .station)
        let entry = NowPlayingTimelineEntry.whosOn(spotlight, recentItems: [], family: family)
        #expect(entry.artistName == "In the studio: Ana Lucía Ríos")
        #expect(entry.songTitle == "DJ Sidechain")
        #expect(entry.artwork == nil)
        #expect(entry.roleLabel == nil)
        #expect(!entry.programLeads)
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

    @Test("A specialty show's entries drop to two recents; a song outside a program keeps all it is given", arguments: [WidgetFamily.systemSmall, .systemMedium, .systemLarge])
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

    @Test("The recents label defaults to Recently Played and carries a specialty entry's Before label")
    func recentsLabel() {
        let item = NowPlayingItem(playcut: recents(1)[0].playcut)
        #expect(NowPlayingTimelineEntry(nowPlayingItem: item, recentItems: [], family: .systemLarge).recentsLabel == "Recently Played")
        #expect(NowPlayingTimelineEntry(headline: headline, logo: nil, recentItems: [], family: .systemLarge, recentsLabel: "Before HW").recentsLabel == "Before HW")
        #expect(NowPlayingTimelineEntry(nowPlayingItem: item, recentItems: [], family: .systemLarge, headline: headline, recentsLabel: "Before HW").recentsLabel == "Before HW")
    }
}

@Suite("NowPlayingTimelineEntry who's-on and guest lines")
struct NowPlayingTimelineEntryWhosOnTests {
    private let program = SpecialtyShowRef(id: 3, slug: "hogwash", name: "Hogwash", shortName: "HW", tagline: "Weird and wonderful")
    private let song = NowPlayingItem(playcut: Playcut(
        id: 1, hour: 0, chronOrderID: 1, timeCreated: 0,
        songTitle: "la paradoja", labelName: nil, artistName: "Juana Molina", releaseTitle: nil
    ))

    private func program(person: String, roleLabel: String?, family: WidgetFamily) -> NowPlayingTimelineEntry {
        NowPlayingTimelineEntry(
            headline: NowPlayingHeadline(program: program, person: person), logo: nil, recentItems: [], family: family, roleLabel: roleLabel
        )
    }

    @Test("A specialty who's-on entry uses the program layout: program bold, the entry's name second, the role label beside them", arguments: [WidgetFamily.systemSmall, .systemMedium, .systemLarge])
    func specialtyWhosOn(family: WidgetFamily) {
        let entry = program(person: "Weirs", roleLabel: "Live in the studio", family: family)
        #expect(entry.artistName == "Hogwash")
        #expect(entry.songTitle == "Weirs")
        #expect(entry.programLeads)
        #expect(entry.roleLabel == "Live in the studio")
    }

    @Test("Without a who's-on entry the role label is absent and the tagline fills its place")
    func specialtyWithoutEntry() {
        let entry = program(person: "DJ Hog", roleLabel: nil, family: .systemMedium)
        #expect(entry.roleLabel == nil)
        #expect(entry.headline?.tagline == "Weird and wonderful")
        #expect(entry.supportingLine == "Weird and wonderful")
        #expect(program(person: "Weirs", roleLabel: "Reading now", family: .systemMedium).supportingLine == "Reading now")
    }

    @Test("A song leading under a guest carries the guest line without touching the song's lines", arguments: [WidgetFamily.systemSmall, .systemMedium, .systemLarge])
    func guestLine(family: WidgetFamily) {
        let entry = NowPlayingTimelineEntry(nowPlayingItem: song, recentItems: [], family: family, guestLine: "In the studio: Ana Lucía Ríos")
        #expect(entry.guestLine == "In the studio: Ana Lucía Ríos")
        #expect(entry.artistName == "Juana Molina")
        #expect(entry.songTitle == "la paradoja")
    }

    @Test("A song with no guest carries no guest line")
    func noGuestLine() {
        #expect(NowPlayingTimelineEntry(nowPlayingItem: song, recentItems: [], family: .systemMedium).guestLine == nil)
    }
}
