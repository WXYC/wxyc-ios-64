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

    // MARK: - Playlist cache back-compat

    @Test("Playlist decoded without onAir defaults to .unknown (v1 / legacy cache)")
    func playlistWithoutOnAirDefaultsToUnknown() throws {
        let json = #"{"playcuts":[],"breakpoints":[],"talksets":[]}"#
        let playlist = try JSONDecoder().decode(Playlist.self, from: Data(json.utf8))
        #expect(playlist.onAir == .unknown)
    }
}
