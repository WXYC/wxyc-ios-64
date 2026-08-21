//
//  LikedSongsEventsTests.swift
//  Analytics
//
//  Tests for the hand-written SongLikeToggled conformance (2026-08-21 identity
//  reversal, docs/plans/likes-identity-capture.md): nil artistId is omitted
//  from properties rather than serialized as a wrapped Optional, a populated
//  artistId round-trips, and album is always present (including "" for a
//  release-less playcut) so it matches the other three identity-bearing
//  events' shape.
//
//  Created by Jake Bromberg on 08/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import Analytics

@Suite("SongLikeToggled")
struct LikedSongsEventsTests {

    // MARK: - Event Name

    @Test("Event name is 'song_like_toggled'")
    func eventName() {
        #expect(SongLikeToggled.name == "song_like_toggled")
    }

    // MARK: - Property Serialization

    @Test("Properties include the lifecycle fields and identity")
    func basicProperties() throws {
        let event = SongLikeToggled(
            action: "like",
            surface: "row",
            totalBucket: "1-9",
            songTitle: "la paradoja",
            artist: "Juana Molina",
            album: "DOGA",
            artistId: 42
        )
        let props = try #require(event.properties)

        #expect(props["action"] as? String == "like")
        #expect(props["surface"] as? String == "row")
        #expect(props["total_bucket"] as? String == "1-9")
        #expect(props["song_title"] as? String == "la paradoja")
        #expect(props["artist"] as? String == "Juana Molina")
        #expect(props["album"] as? String == "DOGA")
        #expect(props["artist_id"] as? Int == 42)
    }

    @Test("Nil artistId omits the key entirely rather than serializing an Optional")
    func nilArtistIdOmitsKey() throws {
        let event = SongLikeToggled(
            action: "unlike",
            surface: "liked_tab",
            totalBucket: "0",
            songTitle: "Back, Baby",
            artist: "Jessica Pratt",
            album: "On Your Own Love Again",
            artistId: nil
        )
        let props = try #require(event.properties)

        #expect(props.keys.contains("artist_id") == false)
    }

    @Test("Album is present even when empty, matching the other identity-bearing events")
    func albumAlwaysPresent() throws {
        let event = SongLikeToggled(
            action: "like",
            surface: "detail",
            totalBucket: "10-49",
            songTitle: "Call Your Name",
            artist: "Chuquimamani-Condori",
            album: "",
            artistId: nil
        )
        let props = try #require(event.properties)

        #expect(props["album"] as? String == "")
    }

    @Test("Default artistId is nil when omitted from the initializer")
    func defaultArtistIdIsNil() {
        let event = SongLikeToggled(
            action: "like",
            surface: "row",
            totalBucket: "0",
            songTitle: "la paradoja",
            artist: "Juana Molina",
            album: "DOGA"
        )

        #expect(event.artistId == nil)
    }
}
