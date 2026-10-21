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

private let newerShowSong = Playcut.stub(id: 11, showID: 43)
private let openUnidentifiedSpecialty = OnAir.dj("DJ MONSTER", show: OnAirShow(id: nil, title: nil, specialty: hogwash))

private let nowPlayingLeadCases: [NowPlayingLeadCase] = [
    NowPlayingLeadCase(name: "song of the open show leads", playcuts: [staleSong, ownSong], onAir: openFreeform, expected: .song(ownSong)),
    NowPlayingLeadCase(name: "specialty show's own song leads over the card", playcuts: [staleSong, ownSong], onAir: openSpecialty, expected: .song(ownSong)),
    NowPlayingLeadCase(name: "song from a newer show than on_air reports does not lead", playcuts: [ownSong, newerShowSong], onAir: openFreeform, expected: .djHandle("Cat Power Hour")),
    NowPlayingLeadCase(name: "specialty show with no song leads with the card", playcuts: [], onAir: openSpecialty, expected: .specialtyCard(hogwash)),
    NowPlayingLeadCase(name: "freeform show with no song leads with the DJ handle", playcuts: [], onAir: openFreeform, expected: .djHandle("Cat Power Hour")),
    NowPlayingLeadCase(name: "previous show's song never leads a specialty show", playcuts: [staleSong], onAir: openSpecialty, expected: .specialtyCard(hogwash)),
    NowPlayingLeadCase(name: "previous show's song never leads a freeform show", playcuts: [staleSong], onAir: openFreeform, expected: .djHandle("Cat Power Hour")),
    NowPlayingLeadCase(name: "playcut without a show id never leads", playcuts: [uncachedSong], onAir: openFreeform, expected: .djHandle("Cat Power Hour")),
    NowPlayingLeadCase(name: "automation leads with nothing", playcuts: [ownSong], onAir: .automation, expected: .nothing),
    NowPlayingLeadCase(name: "unknown on-air keeps the newest song", playcuts: [staleSong, ownSong], onAir: .unknown, expected: .song(ownSong)),
    NowPlayingLeadCase(name: "unknown on-air with no songs leads with nothing", playcuts: [], onAir: .unknown, expected: .nothing),
    NowPlayingLeadCase(name: "show without an id keeps the newest song", playcuts: [staleSong], onAir: .dj("Cat Power Hour"), expected: .song(staleSong)),
    NowPlayingLeadCase(name: "show without an id and no song leads with the DJ handle", playcuts: [], onAir: .dj("Cat Power Hour"), expected: .djHandle("Cat Power Hour")),
    NowPlayingLeadCase(name: "specialty show without an id and no song leads with the card", playcuts: [], onAir: openUnidentifiedSpecialty, expected: .specialtyCard(hogwash)),
]

@Suite("Now Playing Lead Tests")
struct NowPlayingLeadTests {
    @Test("what leads now playing", arguments: nowPlayingLeadCases)
    func leads(_ testCase: NowPlayingLeadCase) {
        let playlist = Playlist.stub(playcuts: testCase.playcuts, onAir: testCase.onAir)

        #expect(playlist.nowPlayingLead == testCase.expected)
    }

    @Test("the lead rule does not change currentPlaycut")
    func currentPlaycutUnchanged() {
        let playlist = Playlist.stub(playcuts: [staleSong], onAir: openFreeform)

        #expect(playlist.currentPlaycut == staleSong)
    }
}
