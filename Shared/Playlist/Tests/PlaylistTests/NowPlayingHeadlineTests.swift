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
    let lead: NowPlayingLead
    let expected: NowPlayingHeadline?
    var testDescription: String { name }
}

private let headlineCases: [NowPlayingHeadlineCase] = [
    NowPlayingHeadlineCase(name: "a specialty card names the program over the person", lead: .specialtyCard(hogwash), expected: NowPlayingHeadline(program: hogwash, person: "DJ Monster")),
    NowPlayingHeadlineCase(name: "a song of the open show leads on its own", lead: .song(Playcut.stub(id: 12, showID: 42)), expected: nil),
    NowPlayingHeadlineCase(name: "a who's-on entry keeps its own lines", lead: .spotlight(SpotlightEntry.stub(id: 13)), expected: nil),
    NowPlayingHeadlineCase(name: "a freeform show has no program to name", lead: .djHandle("Cat Power Hour"), expected: nil),
    NowPlayingHeadlineCase(name: "automation names nothing", lead: .nothing, expected: nil),
]

@Suite("NowPlayingHeadline")
struct NowPlayingHeadlineTests {
    @Test("headline per lead", arguments: headlineCases)
    func headline(_ testCase: NowPlayingHeadlineCase) {
        #expect(testCase.lead.headline(person: "DJ Monster") == testCase.expected)
    }

    @Test("the tagline is the program's, and absent when it has none")
    func tagline() {
        #expect(NowPlayingHeadline(program: hogwash, person: "DJ Monster").tagline == "Weird and wonderful")
        #expect(NowPlayingHeadline(program: untagged, person: "DJ Monster").tagline == nil)
    }
}
