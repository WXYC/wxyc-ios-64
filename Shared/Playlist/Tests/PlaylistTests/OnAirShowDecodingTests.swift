//
//  OnAirShowDecodingTests.swift
//  Playlist
//
//  Verifies that `on_air`'s optional `show_id`, `show_name` and `specialty`
//  decode alongside `dj_name`, that a malformed `specialty` degrades without
//  costing the DJ name, and that the new fields participate in equality and the
//  cache round trip.
//
//  Created by Jake Bromberg on 10/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Playlist
import PlaylistTesting

private let specialtyLiteral = #"""
{"id":3,"slug":"hogwash","name":"Hogwash","short_name":"Hogwash","tagline":"Weird and wonderful",
 "logs_playcuts":true,"default_spotlight_role":"some_future_role",
 "artwork":{"square_url":"https://example.com/hogwash.png"},"accent_color":"#FF8800","unknown_key":1}
"""#

private let hogwash = SpecialtyShowRef(
    id: 3,
    slug: "hogwash",
    name: "Hogwash",
    shortName: "Hogwash",
    tagline: "Weird and wonderful",
    logsPlaycuts: true,
    defaultSpotlightRole: "some_future_role",
    artwork: .init(squareURL: URL(string: "https://example.com/hogwash.png")),
    accentColor: "#FF8800"
)

struct OnAirCase: Sendable, CustomTestStringConvertible {
    let name: String
    let onAirLiteral: String
    let expected: OnAir
    var testDescription: String { name }
}

let onAirCases: [OnAirCase] = [
    OnAirCase(name: "dj_name only", onAirLiteral: #"{"dj_name":"DJ MONSTER"}"#, expected: .dj("DJ MONSTER")),
    OnAirCase(
        name: "all new fields",
        onAirLiteral: #"{"dj_name":"DJ MONSTER","show_id":42,"show_name":"Hogwash Hour","specialty":\#(specialtyLiteral)}"#,
        expected: .dj("DJ MONSTER", show: OnAirShow(id: 42, title: "Hogwash Hour", specialty: hogwash))
    ),
    OnAirCase(
        name: "specialty null",
        onAirLiteral: #"{"dj_name":"DJ MONSTER","show_id":42,"show_name":"Hogwash Hour","specialty":null}"#,
        expected: .dj("DJ MONSTER", show: OnAirShow(id: 42, title: "Hogwash Hour", specialty: nil))
    ),
    OnAirCase(
        name: "malformed specialty keeps the DJ name",
        onAirLiteral: #"{"dj_name":"DJ MONSTER","show_id":42,"show_name":"Hogwash Hour","specialty":{"id":"x"}}"#,
        expected: .dj("DJ MONSTER", show: OnAirShow(id: 42, title: "Hogwash Hour", specialty: nil))
    ),
    OnAirCase(
        name: "specialty of the wrong type keeps the DJ name",
        onAirLiteral: #"{"dj_name":"DJ MONSTER","specialty":"hogwash"}"#,
        expected: .dj("DJ MONSTER")
    ),
    OnAirCase(name: "show_id of the wrong type is dropped", onAirLiteral: #"{"dj_name":"DJ MONSTER","show_id":"x"}"#, expected: .dj("DJ MONSTER")),
]

@Suite("on_air show identity decoding")
struct OnAirShowDecodingTests {

    private func decode(_ onAirLiteral: String) throws -> FlowsheetResponse {
        try JSONDecoder().decode(FlowsheetResponse.self, from: Data(#"{"entries":[],"on_air":\#(onAirLiteral)}"#.utf8))
    }

    @Test("on_air decodes to the expected OnAir", arguments: onAirCases)
    func decodes(_ testCase: OnAirCase) throws {
        #expect(try decode(testCase.onAirLiteral).onAir == testCase.expected)
    }

    @Test("explicit null is automation and absent is unknown")
    func nullAndAbsent() throws {
        #expect(try decode("null").onAir == .automation)
        let absent = try JSONDecoder().decode(FlowsheetResponse.self, from: Data(#"{"entries":[]}"#.utf8))
        #expect(absent.onAir == .unknown)
    }

    @Test("bannerTitle ignores the show")
    func bannerTitleIgnoresShow() {
        #expect(OnAir.dj("DJ MONSTER", show: OnAirShow(id: 1, title: "Hogwash Hour", specialty: hogwash)).bannerTitle == "DJ MONSTER")
    }

    @Test("playlists differing only in show title or specialty are unequal")
    func showFieldsParticipateInEquality() {
        func playlist(title: String?, specialty: SpecialtyShowRef?) -> Playlist {
            .stub(onAir: .dj("DJ MONSTER", show: OnAirShow(id: 42, title: title, specialty: specialty)))
        }
        #expect(playlist(title: "A", specialty: nil) != playlist(title: "B", specialty: nil))
        #expect(playlist(title: "A", specialty: nil) != playlist(title: "A", specialty: hogwash))
        #expect(playlist(title: "A", specialty: hogwash) == playlist(title: "A", specialty: hogwash))
    }

    @Test("OnAir with a show survives a cache round trip; an old cached .dj decodes with no show")
    func cacheRoundTrip() throws {
        let original = OnAir.dj("DJ MONSTER", show: OnAirShow(id: 42, title: "Hogwash Hour", specialty: hogwash))
        let decoded = try JSONDecoder().decode(OnAir.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)

        let old = try JSONDecoder().decode(OnAir.self, from: Data(#"{"dj":{"_0":"DJ MONSTER"}}"#.utf8))
        #expect(old == .dj("DJ MONSTER"))
    }

    @Test("Playcut.showID is set from the entry's show_id, round trips, and is nil in an old cache")
    func playcutShowID() throws {
        let entry = #"{"id":1,"show_id":42,"play_order":1,"add_time":"2024-01-15T14:00:00Z","artist_name":"Juana Molina"}"#
        let response = try JSONDecoder().decode(FlowsheetResponse.self, from: Data(#"{"entries":[\#(entry)]}"#.utf8))
        let playcut = try #require(FlowsheetConverter.convert(response.entries, onAir: response.onAir).playcuts.first)
        #expect(playcut.showID == 42)

        let decoded = try JSONDecoder().decode(Playcut.self, from: JSONEncoder().encode(playcut))
        #expect(decoded.showID == 42)

        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(playcut)) as? [String: Any])
        json["showID"] = nil
        let old = try JSONDecoder().decode(Playcut.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.showID == nil)
    }
}
