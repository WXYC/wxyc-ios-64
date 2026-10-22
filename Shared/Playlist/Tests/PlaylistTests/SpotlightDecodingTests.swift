//
//  SpotlightDecodingTests.swift
//  Playlist
//
//  Verifies that spotlight rows decode into `SpotlightEntry` values for every role
//  (an unknown role included), that `on_air.spotlight` decodes onto `OnAirShow` with the
//  absent, null and object meanings, and that the role-line table reads as designed.
//
//  Created by Jake Bromberg on 10/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Playlist
import PlaylistTesting

private func spotlightRow(role: String, name: String = "Weirs", id: Int = 7, playOrder: Int = 5) -> String {
    #"{"id":\#(id),"show_id":42,"play_order":\#(playOrder),"add_time":"2024-01-15T14:00:00Z","entry_type":"spotlight","spotlight_role":"\#(role)","spotlight_name":"\#(name)","message":"fallback"}"#
}

struct SpotlightRoleCase: Sendable, CustomTestStringConvertible {
    let role: String
    let roleLine: String?
    var testDescription: String { role }
}

private let roleCases: [SpotlightRoleCase] = [
    SpotlightRoleCase(role: "guest", roleLine: "In the studio: Weirs"),
    SpotlightRoleCase(role: "performer", roleLine: "Live in the studio: Weirs"),
    SpotlightRoleCase(role: "reader", roleLine: "Reading now: Weirs"),
    SpotlightRoleCase(role: "dj", roleLine: "Now mixing: Weirs"),
    SpotlightRoleCase(role: "host", roleLine: nil),
    SpotlightRoleCase(role: "ventriloquist", roleLine: "On air: Weirs"),
]

struct SpotlightOnAirCase: Sendable, CustomTestStringConvertible {
    let name: String
    let onAirLiteral: String
    let expected: OnAir
    var testDescription: String { name }
}

private let backyardSpotlight = SpotlightEntry(
    id: 7,
    hour: 1_705_327_200_000,
    chronOrderID: (42 << 32) | 5,
    timeCreated: 1_705_327_200_000,
    showID: 42,
    role: "performer",
    name: "Weirs"
)

private let spotlightOnAirCases: [SpotlightOnAirCase] = [
    SpotlightOnAirCase(
        name: "spotlight absent",
        onAirLiteral: #"{"dj_name":"DJ Sidechain","show_id":42}"#,
        expected: .dj("DJ Sidechain", show: OnAirShow(id: 42, title: nil, specialty: nil))
    ),
    SpotlightOnAirCase(
        name: "spotlight null",
        onAirLiteral: #"{"dj_name":"DJ Sidechain","show_id":42,"spotlight":null}"#,
        expected: .dj("DJ Sidechain", show: OnAirShow(id: 42, title: nil, specialty: nil))
    ),
    SpotlightOnAirCase(
        name: "spotlight present",
        onAirLiteral: #"{"dj_name":"DJ Sidechain","show_id":42,"spotlight":\#(spotlightRow(role: "performer"))}"#,
        expected: .dj("DJ Sidechain", show: OnAirShow(id: 42, title: nil, specialty: nil, spotlight: backyardSpotlight))
    ),
    SpotlightOnAirCase(
        name: "spotlight on a show with no id, title or specialty is kept",
        onAirLiteral: #"{"dj_name":"DJ Sidechain","spotlight":\#(spotlightRow(role: "performer"))}"#,
        expected: .dj("DJ Sidechain", show: OnAirShow(id: nil, title: nil, specialty: nil, spotlight: backyardSpotlight))
    ),
    SpotlightOnAirCase(
        name: "malformed spotlight keeps the DJ name and the show",
        onAirLiteral: #"{"dj_name":"DJ Sidechain","show_id":42,"spotlight":{"id":"x"}}"#,
        expected: .dj("DJ Sidechain", show: OnAirShow(id: 42, title: nil, specialty: nil))
    ),
    SpotlightOnAirCase(
        name: "spotlight of the wrong type keeps the DJ name",
        onAirLiteral: #"{"dj_name":"DJ Sidechain","spotlight":"Weirs"}"#,
        expected: .dj("DJ Sidechain")
    ),
]

@Suite("Spotlight decoding")
struct SpotlightDecodingTests {

    private func decode(onAir: String, entries: [String] = []) throws -> FlowsheetResponse {
        try JSONDecoder().decode(
            FlowsheetResponse.self,
            from: Data(#"{"entries":[\#(entries.joined(separator: ","))],"on_air":\#(onAir)}"#.utf8)
        )
    }

    @Test("a spotlight row becomes a SpotlightEntry for every role, unknown included", arguments: roleCases)
    func rowDecodes(_ testCase: SpotlightRoleCase) throws {
        let response = try decode(onAir: "null", entries: [spotlightRow(role: testCase.role)])
        let playlist = FlowsheetConverter.convert(response.entries, onAir: response.onAir)

        let entry = try #require(playlist.spotlights.first)
        #expect(playlist.spotlights.count == 1)
        #expect(entry.id == 7)
        #expect(entry.showID == 42)
        #expect(entry.chronOrderID == (42 << 32) | 5)
        #expect(entry.role == testCase.role)
        #expect(entry.name == "Weirs")
        #expect(entry.roleLine == testCase.roleLine)
    }

    @Test("a spotlight row with no name is dropped rather than rendered blank")
    func nameless() throws {
        let row = #"{"id":7,"show_id":42,"play_order":5,"add_time":"2024-01-15T14:00:00Z","entry_type":"spotlight","spotlight_role":"guest","message":"x"}"#
        let response = try decode(onAir: "null", entries: [row])

        #expect(FlowsheetConverter.convert(response.entries, onAir: response.onAir).isContentEmpty)
    }

    @Test("on_air.spotlight: absent, null, present, and malformed", arguments: spotlightOnAirCases)
    func onAirSpotlight(_ testCase: SpotlightOnAirCase) throws {
        #expect(try decode(onAir: testCase.onAirLiteral).onAir == testCase.expected)
    }

    @Test("OnAir values differing only in the spotlight are unequal, and so are the playlists")
    func spotlightParticipatesInEquality() {
        func onAir(_ spotlight: SpotlightEntry?) -> OnAir {
            .dj("DJ Sidechain", show: OnAirShow(id: 42, title: nil, specialty: nil, spotlight: spotlight))
        }
        #expect(onAir(nil) != onAir(backyardSpotlight))
        #expect(onAir(backyardSpotlight) == onAir(backyardSpotlight))
        #expect(Playlist.stub(onAir: onAir(nil)) != Playlist.stub(onAir: onAir(backyardSpotlight)))
    }

    @Test("spotlight rows take part in Playlist equality and the cache round trip")
    func playlistRoundTrip() throws {
        let playlist = Playlist(playcuts: [], breakpoints: [], talksets: [], spotlights: [backyardSpotlight])

        #expect(playlist != .empty)
        #expect(!playlist.isContentEmpty)
        #expect(try JSONDecoder().decode(Playlist.self, from: JSONEncoder().encode(playlist)) == playlist)
    }

    @Test("a cached OnAirShow written before spotlights decodes with none")
    func oldCache() throws {
        let old = #"{"dj":{"_0":"DJ Sidechain","show":{"id":42}}}"#
        #expect(try JSONDecoder().decode(OnAir.self, from: Data(old.utf8)) == .dj("DJ Sidechain", show: OnAirShow(id: 42, title: nil, specialty: nil)))
    }
}
