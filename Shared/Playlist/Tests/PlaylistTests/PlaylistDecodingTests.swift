//
//  PlaylistDecodingTests.swift
//  Playlist
//
//  Tests for decoding Playlist JSON from the wxyc.info API endpoint.
//
//  Created by Claude on 01/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Playlist

@Suite("Playlist Decoding Tests")
struct PlaylistDecodingTests {

    @Test("Decodes playlist from wxyc.info JSON fixture")
    func decodesPlaylistFromFixture() throws {
        // Given
        let fixtureURL = Bundle.module.url(
            forResource: "wxyc-info-sample",
            withExtension: "json",
            subdirectory: "Fixtures"
        )!
        let data = try Data(contentsOf: fixtureURL)

        // When
        let playlist = try JSONDecoder().decode(Playlist.self, from: data)

        // Then - Playcuts
        #expect(playlist.playcuts.count == 4)

        let firstPlaycut = playlist.playcuts.first!
        #expect(firstPlaycut.id == 2580200)
        #expect(firstPlaycut.songTitle == "Sguabag / The Sweeper")
        #expect(firstPlaycut.artistName == "Brighde Chaimbeul")
        #expect(firstPlaycut.releaseTitle == "Sunwise")
        #expect(firstPlaycut.labelName == "Glitterbeat Records")
        #expect(firstPlaycut.timeCreated == 1769707664375)
        #expect(firstPlaycut.hour == 1769706000000)
        #expect(firstPlaycut.chronOrderID == 170975006)
        #expect(firstPlaycut.rotation == true)

        // Verify non-rotation playcut
        let nonRotationPlaycut = playlist.playcuts[1]
        #expect(nonRotationPlaycut.rotation == false)

        // Then - Talksets
        #expect(playlist.talksets.count == 2)

        let firstTalkset = playlist.talksets.first!
        #expect(firstTalkset.id == 2580185)
        #expect(firstTalkset.timeCreated == 1769704979553)
        #expect(firstTalkset.hour == 1769702400000)
        #expect(firstTalkset.chronOrderID == 170974033)

        // Then - Breakpoints
        #expect(playlist.breakpoints.count == 2)

        let firstBreakpoint = playlist.breakpoints.first!
        #expect(firstBreakpoint.id == 2580193)
        #expect(firstBreakpoint.timeCreated == 1769706056553)
        #expect(firstBreakpoint.hour == 1769706000000)
        #expect(firstBreakpoint.chronOrderID == 170974041)
    }

    @Test("Decodes HTML entities in playcut fields")
    func decodesHTMLEntitiesInPlaycut() throws {
        // Given - JSON with HTML entities (from real API data)
        let json = """
        {
            "playcuts": [{
                "id": 2580150,
                "rotation": "true",
                "request": "false",
                "songTitle": "Po Moru Je Plovila Gallja",
                "timeCreated": 1769698840701,
                "labelName": "Instant Classic",
                "hour": 1769698800000,
                "artistName": "Raphael Rogi&#324;ski &amp; Ruzicnjak Tajni",
                "chronOrderID": 170973033,
                "releaseTitle": "Bura"
            }],
            "talksets": [],
            "breakpoints": []
        }
        """
        let data = Data(json.utf8)

        // When
        let playlist = try JSONDecoder().decode(Playlist.self, from: data)

        // Then - HTML entities should be decoded
        let playcut = playlist.playcuts.first!
        #expect(playcut.artistName == "Raphael Rogiński & Ruzicnjak Tajni")
    }

    @Test("timeCreated differs from hour in real data")
    func timeCreatedDiffersFromHour() throws {
        // Given
        let fixtureURL = Bundle.module.url(
            forResource: "wxyc-info-sample",
            withExtension: "json",
            subdirectory: "Fixtures"
        )!
        let data = try Data(contentsOf: fixtureURL)

        // When
        let playlist = try JSONDecoder().decode(Playlist.self, from: data)

        // Then - timeCreated should be more precise than hour
        // hour is rounded to the hour, timeCreated is exact
        let playcut = playlist.playcuts.first!
        #expect(playcut.timeCreated != playcut.hour)
        #expect(playcut.timeCreated > playcut.hour)
    }
}
