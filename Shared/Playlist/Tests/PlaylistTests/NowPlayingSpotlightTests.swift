//
//  NowPlayingSpotlightTests.swift
//  Playlist
//
//  Verifies the title, artist, album and artwork source for every lead but a song the system Now Playing info and the
//  widget use while a who's-on entry leads, for specialty and freeform shows.
//
//  Created by Jake Bromberg on 10/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Playlist
import PlaylistTesting

private let backyardBBQ = SpecialtyShowRef(id: 5, slug: "backyard-bbq", name: "Backyard BBQ")
private let weirs = SpotlightEntry.stub(id: 11, role: "performer", name: "Weirs")
private let ana = SpotlightEntry.stub(id: 11, role: "guest", name: "Ana Lucía Ríos")

struct NowPlayingSpotlightCase: Sendable, CustomTestStringConvertible {
    let name: String
    let playlist: Playlist
    let expected: NowPlayingSpotlight?
    var testDescription: String { name }
}

private func playlist(_ dj: String, specialty: SpecialtyShowRef?, spotlight: SpotlightEntry, songs: [Playcut] = []) -> Playlist {
    .stub(playcuts: songs, onAir: .dj(dj, show: OnAirShow(id: 42, title: nil, specialty: specialty, spotlight: spotlight)))
}

private let cases: [NowPlayingSpotlightCase] = [
    NowPlayingSpotlightCase(
        name: "specialty show: program over the entry's name, with the program artwork",
        playlist: playlist("DJ Sidechain", specialty: backyardBBQ, spotlight: weirs),
        expected: NowPlayingSpotlight(title: "Backyard BBQ", artist: "Weirs", album: "WXYC 89.3 FM", artwork: .program(backyardBBQ))
    ),
    NowPlayingSpotlightCase(
        name: "freeform show: the role line over the DJ handle, with the station artwork",
        playlist: playlist("DJ Sidechain", specialty: nil, spotlight: ana),
        expected: NowPlayingSpotlight(title: "In the studio: Ana Lucía Ríos", artist: "DJ Sidechain", album: "WXYC 89.3 FM", artwork: .station)
    ),
    NowPlayingSpotlightCase(
        name: "an entry older than the song does not lead, so there is no spotlight text",
        playlist: playlist("DJ Sidechain", specialty: nil, spotlight: .stub(id: 3), songs: [.stub(id: 10, showID: 42)]),
        expected: nil
    ),
    NowPlayingSpotlightCase(
        name: "specialty show with no song yet: program over the DJ handle, with the program artwork",
        playlist: .stub(onAir: .dj("DJ Sidechain", show: OnAirShow(id: 42, title: nil, specialty: backyardBBQ))),
        expected: NowPlayingSpotlight(title: "Backyard BBQ", artist: "DJ Sidechain", album: "WXYC 89.3 FM", artwork: .program(backyardBBQ))
    ),
    NowPlayingSpotlightCase(
        name: "freeform show with no song yet: the DJ handle over the station line, with the station artwork",
        playlist: .stub(onAir: .dj("DJ Sidechain", show: OnAirShow(id: 42, title: nil, specialty: nil))),
        expected: NowPlayingSpotlight(title: "DJ Sidechain", artist: "WXYC 89.3 FM", album: "WXYC 89.3 FM", artwork: .station)
    ),
    NowPlayingSpotlightCase(
        name: "a song from the open show leads, so there are no spotlight strings",
        playlist: .stub(playcuts: [.stub(id: 10, showID: 42)], onAir: .dj("DJ Sidechain", show: OnAirShow(id: 42, title: nil, specialty: nil))),
        expected: nil
    ),
    NowPlayingSpotlightCase(
        name: "automation leads with nothing",
        playlist: .stub(onAir: .automation),
        expected: nil
    ),
]

@Suite("Now Playing info while a who's-on entry leads")
struct NowPlayingSpotlightTests {
    @Test("title, artist, album and artwork source for every lead but a song", arguments: cases)
    func text(_ testCase: NowPlayingSpotlightCase) {
        #expect(testCase.playlist.nowPlayingSpotlight == testCase.expected)
    }

    @Test("the now line is the role line, on a specialty and a freeform show alike", arguments: [
        (playlist("DJ Sidechain", specialty: backyardBBQ, spotlight: weirs), "Live in the studio: Weirs" as String?),
        (playlist("DJ Sidechain", specialty: nil, spotlight: ana), "In the studio: Ana Lucía Ríos"),
        (playlist("DJ Sidechain", specialty: nil, spotlight: .stub(role: "host", name: "DJ Sidechain")), nil),
        (playlist("DJ Sidechain", specialty: nil, spotlight: .stub(showID: 41, role: "guest", name: "Ana")), nil),
        (Playlist.stub(onAir: .dj("DJ Sidechain")), nil),
        (Playlist.stub(onAir: .automation), nil),
    ] as [(Playlist, String?)])
    func nowLine(playlist: Playlist, expected: String?) {
        #expect(playlist.nowLine == expected)
    }

    @Test("a specialty card carries the now line")
    func cardNowLine() {
        #expect(playlist("DJ Sidechain", specialty: backyardBBQ, spotlight: weirs).specialtyCard?.nowLine == "Live in the studio: Weirs")
    }

    @Test("a leading who's-on entry takes the one now playing header from a non-logging program's card")
    func cardHeaderYieldsToTheEntry() throws {
        let program = SpecialtyShowRef(id: 5, slug: "story-hour", name: "Story Hour", logsPlaycuts: false)
        let card = try #require(playlist("DJ Sidechain", specialty: program, spotlight: weirs).specialtyCard)

        #expect(!card.showsNowPlayingHeader)
        #expect(!card.showsTagline)
    }
}
