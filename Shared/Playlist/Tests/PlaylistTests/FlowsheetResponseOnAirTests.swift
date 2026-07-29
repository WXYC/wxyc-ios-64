//
//  FlowsheetResponseOnAirTests.swift
//  Playlist
//
//  Verifies that the v2 flowsheet response decodes the top-level `on_air` field
//  into the tri-state OnAir by JSON shape (object / null / absent), and that the
//  state is carried through FlowsheetConverter onto the resulting Playlist. This
//  is the fix for the banner showing "AUTO DJ" while a human DJ is live.
//
//  Created by Jake Bromberg on 07/07/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import Concerts
@testable import Playlist

@Suite("Flowsheet on_air Decoding Tests")
struct FlowsheetResponseOnAirTests {

    private func decode(_ json: String) throws -> FlowsheetResponse {
        try JSONDecoder().decode(FlowsheetResponse.self, from: Data(json.utf8))
    }

    // MARK: - Wire decode: the three states are distinguished by JSON shape

    @Test("on_air object with dj_name decodes to .dj")
    func onAirObjectDecodesToDJ() throws {
        let response = try decode(#"{"entries":[],"on_air":{"dj_name":"DJ MONSTER"}}"#)
        #expect(response.onAir == .dj("DJ MONSTER"))
    }

    @Test("on_air null decodes to .automation")
    func onAirNullDecodesToAutomation() throws {
        let response = try decode(#"{"entries":[],"on_air":null}"#)
        #expect(response.onAir == .automation)
    }

    @Test("absent on_air key decodes to .unknown")
    func absentOnAirDecodesToUnknown() throws {
        let response = try decode(#"{"entries":[]}"#)
        #expect(response.onAir == .unknown)
    }

    // MARK: - Propagation onto Playlist

    @Test("FlowsheetConverter carries on_air onto the Playlist")
    func converterCarriesOnAir() {
        let playlist = FlowsheetConverter.convert([], onAir: .dj("DJ MONSTER"))
        #expect(playlist.onAir == .dj("DJ MONSTER"))
    }

    @Test("FlowsheetConverter defaults Playlist.onAir to .unknown")
    func converterDefaultsOnAirToUnknown() {
        let playlist = FlowsheetConverter.convert([])
        #expect(playlist.onAir == .unknown)
    }

    @Test("decode then convert yields a Playlist reporting the live DJ")
    func decodeThenConvertReportsLiveDJ() throws {
        let response = try decode(#"{"entries":[],"on_air":{"dj_name":"DJ MONSTER"}}"#)
        let playlist = FlowsheetConverter.convert(response.entries, onAir: response.onAir)
        #expect(playlist.onAir.bannerTitle == "DJ MONSTER")
    }

    // MARK: - Robustness: a malformed on_air must never fail the whole decode

    // A minimal but valid v2 track entry (id / play_order / add_time are the only
    // non-optional fields), so these fixtures also prove real entries survive.
    private let oneEntry = #"{"id":1,"play_order":1,"add_time":"2024-01-15T14:00:00Z"}"#

    @Test(
        "a malformed on_air degrades to .unknown without dropping entries",
        arguments: [
            #""DJ X""#,          // string, not an object
            "5",                  // number
            "[]",                 // array
            "{}",                 // object missing dj_name
            #"{"name":"DJ X"}"#,  // object with the wrong key
            #"{"dj_name":123}"#,  // dj_name is not a string
            #"{"dj_name":""}"#,   // empty dj_name → blank banner otherwise
            #"{"dj_name":"   "}"#, // whitespace-only dj_name
        ]
    )
    func malformedOnAirDegradesToUnknown(_ onAirLiteral: String) throws {
        let response = try decode(#"{"entries":[\#(oneEntry)],"on_air":\#(onAirLiteral)}"#)
        #expect(response.onAir == .unknown)
        #expect(response.entries.count == 1)   // the feed is never nuked by a bad on_air
        #expect(response.entries.first?.id == 1)
    }

    @Test("a well-formed on_air still decodes alongside non-empty entries")
    func wellFormedOnAirWithEntries() throws {
        let response = try decode(#"{"entries":[\#(oneEntry)],"on_air":{"dj_name":"DJ MONSTER"}}"#)
        #expect(response.onAir == .dj("DJ MONSTER"))
        #expect(response.entries.count == 1)
    }

    @Test("a padded dj_name is trimmed for display")
    func paddedDJNameIsTrimmed() throws {
        let response = try decode(#"{"entries":[],"on_air":{"dj_name":"  DJ MONSTER  "}}"#)
        #expect(response.onAir == .dj("DJ MONSTER"))
    }

    // MARK: - Robustness: a malformed embedded upcoming_show must not nuke the feed

    // A minimal v2 track entry carrying an embedded `upcoming_show`. The embed is
    // present but malformed, so it must degrade to nil rather than throwing and
    // failing the whole atomic `[FlowsheetEntry]` decode (which would freeze every
    // now-playing update over a cosmetic CTA).
    private func entryWithUpcomingShow(_ upcomingShowLiteral: String) -> String {
        #"{"id":7,"play_order":1,"add_time":"2024-01-15T14:00:00Z","artist_name":"Chuquimamani-Condori","upcoming_show":\#(upcomingShowLiteral)}"#
    }

    @Test(
        "a present-but-malformed upcoming_show degrades to nil without dropping the entry",
        arguments: [
            // missing the required `venue` sub-field (a backend join regression)
            #"{"id":99,"starts_on":"2026-08-01","headlining_artist_raw":"X","supporting_artists_raw":[],"status":"on_sale"}"#,
            // `starts_on` is not a well-formed yyyy-MM-dd
            #"{"id":99,"venue":{"id":1,"slug":"v","name":"N","city":"C","state":"NC"},"starts_on":"not-a-date","headlining_artist_raw":"X","supporting_artists_raw":[],"status":"on_sale"}"#,
            // missing the required `headlining_artist_raw`
            #"{"id":99,"venue":{"id":1,"slug":"v","name":"N","city":"C","state":"NC"},"starts_on":"2026-08-01","supporting_artists_raw":[],"status":"on_sale"}"#,
            // missing the required `id`
            #"{"venue":{"id":1,"slug":"v","name":"N","city":"C","state":"NC"},"starts_on":"2026-08-01","headlining_artist_raw":"X","supporting_artists_raw":[],"status":"on_sale"}"#,
        ]
    )
    func malformedUpcomingShowDegradesToNil(_ upcomingShowLiteral: String) throws {
        let response = try decode(#"{"entries":[\#(entryWithUpcomingShow(upcomingShowLiteral))]}"#)
        #expect(response.entries.count == 1)   // the feed is never nuked by a bad embed
        #expect(response.entries.first?.id == 7)
        #expect(response.entries.first?.upcoming_show?.concert == nil)

        // …and it stays nil through the converter onto the Playcut.
        let playlist = FlowsheetConverter.convert(response.entries, onAir: response.onAir)
        #expect(playlist.playcuts.first?.upcomingShow == nil)
    }

    @Test("a well-formed upcoming_show survives the atomic feed decode and reaches the playcut")
    func wellFormedUpcomingShowReachesPlaycut() throws {
        let wellFormed = #"{"id":99,"venue":{"id":1,"slug":"cats-cradle","name":"Cat's Cradle","city":"Carrboro","state":"NC"},"starts_on":"2026-08-01","headlining_artist_raw":"Chuquimamani-Condori","supporting_artists_raw":[],"status":"sold_out"}"#
        let response = try decode(#"{"entries":[\#(entryWithUpcomingShow(wellFormed))]}"#)
        #expect(response.entries.first?.upcoming_show?.concert?.id == 99)

        let playlist = FlowsheetConverter.convert(response.entries, onAir: response.onAir)
        #expect(playlist.playcuts.first?.upcomingShow?.id == 99)
        #expect(playlist.playcuts.first?.upcomingShow?.status == .soldOut)
    }

    // MARK: - Robustness: a malformed critic_reviews item must not nuke the feed (#695)

    // A minimal v2 track entry carrying an embedded `critic_reviews` array. One
    // item is malformed, so a per-item tolerant decode must drop just that item
    // rather than throwing and failing the whole atomic `[FlowsheetEntry]`
    // decode — the same discipline as `upcoming_show` above, applied per array
    // element instead of per optional field.
    private func entryWithCriticReviews(_ criticReviewsLiteral: String) -> String {
        #"{"id":8,"play_order":1,"add_time":"2024-01-15T14:00:00Z","artist_name":"Juana Molina","critic_reviews":\#(criticReviewsLiteral)}"#
    }

    private let wellFormedReview = #"{"source":"The Quietus","url":"https://thequietus.com/a/1","snippet":"Great."}"#

    @Test("an array containing one malformed critic_reviews item keeps the well-formed one, drops only the bad one")
    func oneMalformedItemIsDroppedFromTheArray() throws {
        // First item is missing the required `url`; second is well-formed.
        let criticReviewsLiteral = #"[{"source":"The Quietus","snippet":"Great."}, \#(wellFormedReview)]"#
        let response = try decode(#"{"entries":[\#(entryWithCriticReviews(criticReviewsLiteral))]}"#)
        #expect(response.entries.count == 1)   // the feed is never nuked by a bad review item
        #expect(response.entries.first?.id == 8)
        #expect(response.entries.first?.criticReviews?.count == 1)
        #expect(response.entries.first?.criticReviews?.first?.url.absoluteString == "https://thequietus.com/a/1")

        // …and the survivor reaches the playcut through the converter.
        let playlist = FlowsheetConverter.convert(response.entries, onAir: response.onAir)
        #expect(playlist.playcuts.first?.criticReviews?.count == 1)
    }

    @Test(
        "an item with a blank/unparseable url is dropped by the shared URL-validation policy, not a decode failure",
        arguments: [
            #"[{"source":"The Quietus","url":"","snippet":"Great."}]"#,
            #"[{"source":"The Quietus","url":"   ","snippet":"Great."}]"#,
        ]
    )
    func itemWithBadURLIsDropped(_ criticReviewsLiteral: String) throws {
        let response = try decode(#"{"entries":[\#(entryWithCriticReviews(criticReviewsLiteral))]}"#)
        #expect(response.entries.count == 1)
        // Every item was structurally decodable but failed URL validation, so
        // the filtered result is empty — which collapses to nil, not [].
        #expect(response.entries.first?.criticReviews == nil)
    }

    @Test("absent critic_reviews decodes to nil")
    func absentCriticReviewsDecodesToNil() throws {
        let response = try decode(#"{"entries":[\#(oneEntry)]}"#)
        #expect(response.entries.first?.criticReviews == nil)
    }

    @Test("a well-formed critic_reviews array survives the atomic feed decode and reaches the playcut")
    func wellFormedCriticReviewsReachesPlaycut() throws {
        let response = try decode(#"{"entries":[\#(entryWithCriticReviews("[\(wellFormedReview)]"))]}"#)
        #expect(response.entries.first?.criticReviews?.count == 1)
        #expect(response.entries.first?.criticReviews?.first?.source == "The Quietus")

        let playlist = FlowsheetConverter.convert(response.entries, onAir: response.onAir)
        #expect(playlist.playcuts.first?.criticReviews?.first?.snippet == "Great.")
    }

    // MARK: - Playlist cache back-compat

    @Test("Playlist decoded without onAir defaults to .unknown (v1 / legacy cache)")
    func playlistWithoutOnAirDefaultsToUnknown() throws {
        let json = #"{"playcuts":[],"breakpoints":[],"talksets":[]}"#
        let playlist = try JSONDecoder().decode(Playlist.self, from: Data(json.utf8))
        #expect(playlist.onAir == .unknown)
    }
}
