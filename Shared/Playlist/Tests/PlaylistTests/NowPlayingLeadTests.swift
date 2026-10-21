//
//  NowPlayingLeadTests.swift
//  Playlist
//
//  Verifies the pure rule that decides what leads now playing: the open show's
//  current song, the specialty card, the DJ handle, or nothing, including the
//  stale-song rule that keeps a previous show's last song from leading.
//
//  Created by Jake Bromberg on 10/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Playlist
import PlaylistTesting

private let hogwash = SpecialtyShowRef(
    id: 3,
    slug: "hogwash",
    name: "Hogwash",
    shortName: nil,
    tagline: "Weird and wonderful",
    logsPlaycuts: false,
    defaultSpotlightRole: nil,
    artwork: nil,
    accentColor: nil
)

private let openFreeform = OnAir.dj("Cat Power Hour", show: OnAirShow(id: 42, title: nil, specialty: nil))
private let openSpecialty = OnAir.dj("DJ MONSTER", show: OnAirShow(id: 42, title: "Hogwash Hour", specialty: hogwash))

private let ownSong = Playcut.stub(id: 10, showID: 42)
private let staleSong = Playcut.stub(id: 9, showID: 41)
private let uncachedSong = Playcut.stub(id: 8, showID: nil)

struct NowPlayingLeadCase: Sendable, CustomTestStringConvertible {
    let name: String
    let playcuts: [Playcut]
    let onAir: OnAir
    let expected: NowPlayingLead
    var testDescription: String { name }
}

private let nowPlayingLeadCases: [NowPlayingLeadCase] = [
    NowPlayingLeadCase(name: "song of the open show leads", playcuts: [staleSong, ownSong], onAir: openFreeform, expected: .song(ownSong)),
    NowPlayingLeadCase(name: "specialty show with no song leads with the card", playcuts: [], onAir: openSpecialty, expected: .specialtyCard(hogwash)),
    NowPlayingLeadCase(name: "freeform show with no song leads with the DJ handle", playcuts: [], onAir: openFreeform, expected: .djHandle("Cat Power Hour")),
    NowPlayingLeadCase(name: "previous show's song never leads a specialty show", playcuts: [staleSong], onAir: openSpecialty, expected: .specialtyCard(hogwash)),
    NowPlayingLeadCase(name: "previous show's song never leads a freeform show", playcuts: [staleSong], onAir: openFreeform, expected: .djHandle("Cat Power Hour")),
    NowPlayingLeadCase(name: "playcut without a show id never leads", playcuts: [uncachedSong], onAir: openFreeform, expected: .djHandle("Cat Power Hour")),
    NowPlayingLeadCase(name: "automation leads with nothing", playcuts: [ownSong], onAir: .automation, expected: .none),
    NowPlayingLeadCase(name: "unknown on-air keeps the newest song", playcuts: [staleSong, ownSong], onAir: .unknown, expected: .song(ownSong)),
    NowPlayingLeadCase(name: "unknown on-air with no songs leads with nothing", playcuts: [], onAir: .unknown, expected: .none),
    NowPlayingLeadCase(name: "show without an id keeps the newest song", playcuts: [staleSong], onAir: .dj("Cat Power Hour"), expected: .song(staleSong)),
]

@Suite("Now Playing Lead Tests")
struct NowPlayingLeadTests {
    @Test("what leads now playing", arguments: nowPlayingLeadCases)
    func leads(_ testCase: NowPlayingLeadCase) {
        let playlist = Playlist.stub(playcuts: testCase.playcuts, onAir: testCase.onAir)

        #expect(playlist.nowPlayingLead == testCase.expected)
    }

    @Test("currentPlaycut is the leading song, if any")
    func currentPlaycutFollowsLead() {
        #expect(Playlist.stub(playcuts: [staleSong], onAir: openFreeform).currentPlaycut == nil)
        #expect(Playlist.stub(playcuts: [staleSong, ownSong], onAir: openFreeform).currentPlaycut == ownSong)
    }
}

// MARK: - Consumers of the lead: list headers and the widget

struct SectionCase: Sendable, CustomTestStringConvertible {
    let name: String
    let playcuts: [Playcut]
    let onAir: OnAir
    /// Expected header for each playcut, newest first.
    let expected: [PlaylistSection?]
    var testDescription: String { name }
}

private let newestFirst: [Playcut] = [ownSong, staleSong]

private let sectionCases: [SectionCase] = [
    SectionCase(name: "open show's song is now playing, the next is recent", playcuts: newestFirst, onAir: openFreeform, expected: [.nowPlaying, .recentlyPlayed]),
    SectionCase(name: "previous show's last song is never labelled now playing", playcuts: [staleSong, Playcut.stub(id: 7, showID: 40)], onAir: openFreeform, expected: [.recentlyPlayed, nil]),
    SectionCase(name: "automation labels nothing now playing", playcuts: newestFirst, onAir: .automation, expected: [.recentlyPlayed, nil]),
    SectionCase(name: "unknown on-air keeps the newest as now playing", playcuts: newestFirst, onAir: .unknown, expected: [.nowPlaying, .recentlyPlayed]),
]

@Suite("Now Playing Lead consumers")
struct NowPlayingLeadConsumerTests {
    @Test("section header for each playcut row", arguments: sectionCases)
    func sections(_ testCase: SectionCase) {
        let playlist = Playlist.stub(playcuts: testCase.playcuts, onAir: testCase.onAir)
        let headers = testCase.playcuts.enumerated().map { index, playcut in
            playlist.section(forPlaycutAt: index, id: playcut.id)
        }

        #expect(headers == testCase.expected)
    }

    @Test("widget recents skip the leading song and keep the rest when no song leads")
    func widgetRecents() {
        let leading = Playlist.stub(playcuts: [staleSong, ownSong], onAir: openFreeform)
        #expect(leading.widgetRecents.map(\.id) == [9])

        let noSongLeads = Playlist.stub(playcuts: [staleSong, ownSong], onAir: .automation)
        #expect(noSongLeads.widgetRecents.map(\.id) == [10, 9])
    }

    @Test("headline names the DJ or the specialty show, and nothing for automation")
    func headlines() {
        #expect(NowPlayingLead.djHandle("Cat Power Hour").headline == NowPlayingHeadline(title: "Cat Power Hour", detail: "is on the air"))
        #expect(NowPlayingLead.specialtyCard(hogwash).headline == NowPlayingHeadline(title: "Hogwash", detail: "Weird and wonderful"))
        #expect(NowPlayingLead.none.headline == NowPlayingHeadline(title: "Auto DJ", detail: "Tune in to WXYC 89.3 FM"))
        #expect(NowPlayingLead.song(ownSong).headline == nil)
    }
}
