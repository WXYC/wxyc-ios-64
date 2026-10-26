//
//  NowPlayingHeadlineTests.swift
//  Playlist
//
//  Verifies which leads name a specialty program over its person, and what the headline carries.
//
//  Created by Jake Bromberg on 10/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Playlist
import PlaylistTesting

private let hogwash = SpecialtyShowRef.taggedStub
private let untagged = SpecialtyShowRef.untaggedStub

struct NowPlayingHeadlineCase: Sendable, CustomTestStringConvertible {
    let name: String
    let playlist: Playlist
    let expected: NowPlayingHeadline?
    /// Whether `nowPlayingSpotlight` names the headline's person too: false while a song leads (no strings),
    /// or when the lead is not the entry the person line came from.
    let spotlightSharesPerson: Bool
    var testDescription: String { name }
}

private func onAir(_ show: OnAirShow?, songs: [Playcut] = []) -> Playlist {
    .stub(playcuts: songs, onAir: .dj("DJ Monster", show: show))
}

private let headlineCases: [NowPlayingHeadlineCase] = [
    NowPlayingHeadlineCase(
        name: "a specialty show with no song names the program over the DJ handle",
        playlist: onAir(OnAirShow(id: 42, title: nil, specialty: hogwash)),
        expected: NowPlayingHeadline(program: hogwash, person: "DJ Monster"),
        spotlightSharesPerson: true
    ),
    NowPlayingHeadlineCase(
        name: "a song of the open show leads, and the program is still on the air",
        playlist: onAir(OnAirShow(id: 42, title: nil, specialty: hogwash), songs: [.stub(id: 12, showID: 42)]),
        expected: NowPlayingHeadline(program: hogwash, person: "DJ Monster", showsTagline: false),
        spotlightSharesPerson: false
    ),
    NowPlayingHeadlineCase(
        name: "a who's-on entry leads, and the program is still on the air",
        playlist: onAir(OnAirShow(id: 42, title: nil, specialty: hogwash, spotlight: .stub(id: 13, role: "performer", name: "Weirs"))),
        expected: NowPlayingHeadline(program: hogwash, person: "Weirs", showsTagline: false),
        spotlightSharesPerson: true
    ),
    NowPlayingHeadlineCase(
        name: "a host entry never leads: the tagline stays and the person line is the DJ handle",
        playlist: onAir(OnAirShow(id: 42, title: nil, specialty: hogwash, spotlight: .stub(id: 13, role: "host", name: "DJ Monster"))),
        expected: NowPlayingHeadline(program: hogwash, person: "DJ Monster"),
        spotlightSharesPerson: true
    ),
    NowPlayingHeadlineCase(
        name: "an entry from another show leaves the DJ handle as the person",
        playlist: onAir(OnAirShow(id: 42, title: nil, specialty: hogwash, spotlight: .stub(id: 13, showID: 41, role: "performer", name: "Weirs"))),
        expected: NowPlayingHeadline(program: hogwash, person: "DJ Monster"),
        spotlightSharesPerson: true
    ),
    NowPlayingHeadlineCase(
        name: "a specialty show whose id is unknown still names its program",
        playlist: onAir(OnAirShow(id: nil, title: nil, specialty: hogwash)),
        expected: NowPlayingHeadline(program: hogwash, person: "DJ Monster"),
        spotlightSharesPerson: true
    ),
    NowPlayingHeadlineCase(
        name: "a freeform show has no program to name",
        playlist: onAir(OnAirShow(id: 42, title: nil, specialty: nil)),
        expected: nil,
        spotlightSharesPerson: false
    ),
    NowPlayingHeadlineCase(
        name: "a DJ with no show information has no program to name",
        playlist: onAir(nil),
        expected: nil,
        spotlightSharesPerson: false
    ),
    NowPlayingHeadlineCase(
        name: "automation names nothing",
        playlist: .stub(onAir: .automation),
        expected: nil,
        spotlightSharesPerson: false
    ),
]

@Suite("NowPlayingHeadline")
struct NowPlayingHeadlineTests {
    @Test("the program on the air, whatever leads", arguments: headlineCases)
    func programHeadline(_ testCase: NowPlayingHeadlineCase) {
        #expect(testCase.playlist.programHeadline == testCase.expected)
    }

    @Test("nowPlayingSpotlight names the same program, and the same person while the card leads", arguments: headlineCases)
    func spotlightAgrees(_ testCase: NowPlayingHeadlineCase) throws {
        guard let headline = testCase.playlist.programHeadline,
              let spotlight = testCase.playlist.nowPlayingSpotlight else { return }
        #expect(spotlight.artwork == .program(headline.program))
        #expect(spotlight.title == headline.program.name)
        #expect(testCase.spotlightSharesPerson == (spotlight.artist == headline.person))
    }

    @Test("the headline's tagline agrees with SpecialtyCard.showsTagline across the on-air states", arguments: headlineCases)
    func taglineAgreesWithCard(_ testCase: NowPlayingHeadlineCase) {
        let playlist = testCase.playlist
        #expect(playlist.programHeadline?.showsTagline == playlist.specialtyCard?.showsTagline)
        #expect((playlist.programHeadline?.tagline != nil) == (playlist.specialtyCard?.showsTagline == true))
    }

    @Test("the tagline is the program's, and absent when it has none")
    func tagline() {
        #expect(NowPlayingHeadline(program: hogwash, person: "DJ Monster").tagline == "Weird and wonderful")
        #expect(NowPlayingHeadline(program: untagged, person: "DJ Monster").tagline == nil)
        #expect(NowPlayingHeadline(program: hogwash, person: "DJ Monster", showsTagline: false).tagline == nil)
    }
}
