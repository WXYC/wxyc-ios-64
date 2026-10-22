//
//  SpecialtyCardTests.swift
//  Playlist
//
//  Verifies when a specialty program's card shows, where it sits relative to the
//  song list, when it carries the tagline, and how its text tile is derived.
//
//  Created by Jake Bromberg on 10/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Playlist
import PlaylistTesting

private func program(logsPlaycuts: Bool?, shortName: String? = nil, accentColor: String? = nil) -> SpecialtyShowRef {
    SpecialtyShowRef(
        id: 3,
        slug: "hogwash",
        name: "Hogwash",
        shortName: shortName,
        tagline: "Weird and wonderful",
        logsPlaycuts: logsPlaycuts,
        accentColor: accentColor
    )
}

private func onAir(_ specialty: SpecialtyShowRef?, handle: String = "DJ MONSTER") -> OnAir {
    .dj(handle, show: OnAirShow(id: 42, title: "Hogwash Hour", specialty: specialty))
}

private let ownSong = Playcut.stub(id: 10, showID: 42)
private let staleSong = Playcut.stub(id: 9, showID: 41)

struct SpecialtyCardCase: Sendable, CustomTestStringConvertible {
    let name: String
    let playcuts: [Playcut]
    let onAir: OnAir
    let placement: SpecialtyCard.Placement?
    let showsTagline: Bool
    /// Whether the card draws its own "now playing" header: only when it is the now-playing item.
    let showsNowPlayingHeader: Bool
    var testDescription: String { name }
}

private let specialtyCardCases: [SpecialtyCardCase] = [
    SpecialtyCardCase(name: "logging show with no song sits above the list with the tagline", playcuts: [staleSong], onAir: onAir(program(logsPlaycuts: true)), placement: .aboveSongList, showsTagline: true, showsNowPlayingHeader: false),
    SpecialtyCardCase(name: "logging show keeps the card above the list once a song lands, without the tagline", playcuts: [staleSong, ownSong], onAir: onAir(program(logsPlaycuts: true)), placement: .aboveSongList, showsTagline: false, showsNowPlayingHeader: false),
    SpecialtyCardCase(name: "non-logging show's card is the now-playing item", playcuts: [staleSong], onAir: onAir(program(logsPlaycuts: false)), placement: .nowPlaying, showsTagline: true, showsNowPlayingHeader: true),
    SpecialtyCardCase(name: "non-logging show that logs a song anyway leaves the one header to the leading song", playcuts: [staleSong, ownSong], onAir: onAir(program(logsPlaycuts: false)), placement: .nowPlaying, showsTagline: false, showsNowPlayingHeader: false),
    SpecialtyCardCase(name: "unspecified logging flag keeps the song list", playcuts: [], onAir: onAir(program(logsPlaycuts: nil)), placement: .aboveSongList, showsTagline: true, showsNowPlayingHeader: false),
    SpecialtyCardCase(name: "freeform show has no card", playcuts: [ownSong], onAir: onAir(nil), placement: nil, showsTagline: false, showsNowPlayingHeader: false),
    SpecialtyCardCase(name: "automation has no card", playcuts: [ownSong], onAir: .automation, placement: nil, showsTagline: false, showsNowPlayingHeader: false),
    SpecialtyCardCase(name: "unknown on-air has no card", playcuts: [], onAir: .unknown, placement: nil, showsTagline: false, showsNowPlayingHeader: false),
]

@Suite("Specialty Card Tests")
struct SpecialtyCardTests {
    @Test("Card placement, tagline, and now-playing header", arguments: specialtyCardCases)
    func card(_ testCase: SpecialtyCardCase) {
        let playlist = Playlist.stub(playcuts: testCase.playcuts, onAir: testCase.onAir)
        let card = playlist.specialtyCard
        #expect(card?.placement == testCase.placement)
        #expect(card?.showsTagline ?? false == testCase.showsTagline)
        #expect(card?.showsNowPlayingHeader ?? false == testCase.showsNowPlayingHeader)
    }

    @Test("Card carries the program, the show name, and the DJ handle")
    func cardIdentity() throws {
        let playlist = Playlist.stub(playcuts: [], onAir: onAir(program(logsPlaycuts: true)))
        let card = try #require(playlist.specialtyCard)
        #expect(card.program.name == "Hogwash")
        #expect(card.showName == "Hogwash Hour")
        #expect(card.djHandle == "DJ MONSTER")
    }

    @Test("Tile text is the short name, else the name", arguments: [("HW", "HW"), (nil, "Hogwash")] as [(String?, String)])
    func tileText(shortName: String?, expected: String) {
        #expect(program(logsPlaycuts: true, shortName: shortName).tileText == expected)
    }

    @Test("Accent color parses from hex", arguments: [
        ("#FF8800", [1.0, 136.0 / 255, 0.0]),
        ("0000FF", [0.0, 0.0, 1.0]),
    ] as [(String, [Double])])
    func accent(hex: String, expected: [Double]) throws {
        let rgb = try #require(program(logsPlaycuts: true, accentColor: hex).accentRGB)
        #expect([rgb.red, rgb.green, rgb.blue] == expected)
    }

    @Test("Missing or malformed accent color is nil", arguments: [nil, "", "#FFF", "#GGGGGG"] as [String?])
    func badAccent(hex: String?) {
        #expect(program(logsPlaycuts: true, accentColor: hex).accentRGB == nil)
    }
}
