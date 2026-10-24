//
//  ShowHeaderTests.swift
//  Playlist
//
//  Verifies the top-level `shows` array: tolerant decoding by key presence, and the
//  per-show headers the scrollback draws from it.
//
//  Created by Jake Bromberg on 10/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Playlist
import PlaylistTesting

private let hogwashLiteral = ##"{"id":3,"slug":"hogwash","name":"Hogwash","short_name":"HW","accent_color":"#B3261E","artwork":{"square_url":"https://example.com/hogwash.png"}}"##

struct ShowsDecodingCase: Sendable, CustomTestStringConvertible {
    let name: String
    let json: String
    let expected: [UInt64: PlaylistShow]
    var testDescription: String { name }
}

private let hogwash = SpecialtyShowRef(
    id: 3, slug: "hogwash", name: "Hogwash", shortName: "HW",
    artwork: .init(squareURL: URL(string: "https://example.com/hogwash.png")), accentColor: "#B3261E"
)

let showsDecodingCases: [ShowsDecodingCase] = [
    ShowsDecodingCase(name: "shows absent", json: #"{"entries":[]}"#, expected: [:]),
    ShowsDecodingCase(name: "shows empty", json: #"{"entries":[],"shows":[]}"#, expected: [:]),
    ShowsDecodingCase(
        name: "one specialty and one freeform show",
        json: #"""
        {"entries":[],"shows":[
          {"id":42,"show_name":"Hogwash Hour","dj_name":"DJ Monster","specialty_id":3,"specialty":\#(hogwashLiteral),"start_time":"2026-10-20T20:00:00Z","end_time":null,"unknown":1},
          {"id":41,"show_name":null,"dj_name":"DJ Moth","specialty_id":null,"specialty":null,"start_time":"2026-10-20T18:00:00Z","end_time":"2026-10-20T20:00:00Z"}]}
        """#,
        expected: [
            42: PlaylistShow(id: 42, showName: "Hogwash Hour", djName: "DJ Monster", specialty: hogwash),
            41: PlaylistShow(id: 41, showName: nil, djName: "DJ Moth", specialty: nil),
        ]
    ),
    ShowsDecodingCase(
        name: "a malformed show object is skipped",
        json: #"{"entries":[],"shows":[{"id":"x"},{"id":41,"dj_name":"DJ Moth"}]}"#,
        expected: [41: PlaylistShow(id: 41, showName: nil, djName: "DJ Moth", specialty: nil)]
    ),
    ShowsDecodingCase(name: "shows of the wrong type", json: #"{"entries":[],"shows":"x"}"#, expected: [:]),
]

@Suite("Show headers")
struct ShowHeaderTests {

    @Test("shows decode tolerantly and key by id", arguments: showsDecodingCases)
    func decodes(_ testCase: ShowsDecodingCase) throws {
        let response = try JSONDecoder().decode(FlowsheetResponse.self, from: Data(testCase.json.utf8))
        let playlist = FlowsheetConverter.convert(response.entries, onAir: response.onAir, shows: response.shows)
        #expect(playlist.shows == testCase.expected)
    }

    @Test("shows survive a cache round trip and participate in equality")
    func roundTripAndEquality() throws {
        let show = PlaylistShow(id: 42, showName: nil, djName: "DJ Monster", specialty: hogwash)
        let playlist = Playlist(playcuts: [], breakpoints: [], talksets: [], shows: [42: show])
        #expect(try JSONDecoder().decode(Playlist.self, from: JSONEncoder().encode(playlist)) == playlist)
        #expect(playlist != Playlist.stub())
    }

    private func headers(_ playlist: Playlist) -> [UInt64: ShowHeader] {
        playlist.showHeaders(of: playlist.timelineItems)
    }

    @Test("a specialty show's newest row opens its header, with the show name and DJ handle")
    func specialtyHeader() {
        let playlist = Playlist(
            playcuts: [.stub(id: 9, chronOrderID: 9, showID: 42), .stub(id: 8, chronOrderID: 8, showID: 42), .stub(id: 5, chronOrderID: 5, showID: 41)],
            breakpoints: [], talksets: [],
            shows: [
                42: PlaylistShow(id: 42, showName: "Hogwash Hour", djName: "DJ Monster", specialty: hogwash),
                41: PlaylistShow(id: 41, showName: nil, djName: "DJ Moth", specialty: nil),
            ]
        )
        #expect(headers(playlist) == [9: ShowHeader(program: hogwash, showName: "Hogwash Hour", djHandle: "DJ Monster")])
    }

    @Test("the subtitle is absent when the airing has no show name")
    func noSubtitle() {
        let playlist = Playlist(
            playcuts: [.stub(id: 9, chronOrderID: 9, showID: 42)], breakpoints: [], talksets: [],
            shows: [42: PlaylistShow(id: 42, showName: nil, djName: "DJ Monster", specialty: hogwash)]
        )
        #expect(headers(playlist)[9]?.showName == nil)
    }

    @Test("a row whose show is missing from shows still renders, with no header")
    func missingShow() {
        let playlist = Playlist(
            playcuts: [.stub(id: 9, chronOrderID: 9, showID: 42), .stub(id: 5, chronOrderID: 5, showID: 41)],
            breakpoints: [], talksets: [],
            shows: [41: PlaylistShow(id: 41, showName: nil, djName: nil, specialty: hogwash)]
        )
        #expect(playlist.timelineItems.count == 2)
        #expect(headers(playlist).keys.sorted() == [5])
    }

    @Test("absent shows means no headers")
    func noShows() {
        #expect(headers(.stub(playcuts: [.stub(id: 9, chronOrderID: 9, showID: 42)])).isEmpty)
    }
}
