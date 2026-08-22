//
//  UIEventsTests.swift
//  Analytics
//
//  Property-shape coverage for the `songTitle` field added to the three
//  identity-bearing UI events (2026-08-21 identity reversal,
//  docs/plans/likes-identity-capture.md). Before this, no event in the app
//  captured a song title at all; these three carried `artist`/`album` only.
//
//  Created by Jake Bromberg on 08/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import Analytics

@Suite("UIEvents")
struct UIEventsTests {

    @Test("PlaycutDetailViewPresented carries song_title alongside artist and album")
    func playcutDetailViewPresentedCarriesSongTitle() throws {
        let event = PlaycutDetailViewPresented(songTitle: "la paradoja", artist: "Juana Molina", album: "DOGA")
        let props = try #require(event.properties)

        #expect(props["song_title"] as? String == "la paradoja")
        #expect(props["artist"] as? String == "Juana Molina")
        #expect(props["album"] as? String == "DOGA")
    }

    @Test("StreamingLinkTapped carries song_title alongside service, artist, and album")
    func streamingLinkTappedCarriesSongTitle() throws {
        let event = StreamingLinkTapped(
            service: "Spotify", songTitle: "Back, Baby", artist: "Jessica Pratt", album: "On Your Own Love Again"
        )
        let props = try #require(event.properties)

        #expect(props["song_title"] as? String == "Back, Baby")
        #expect(props["service"] as? String == "Spotify")
        #expect(props["artist"] as? String == "Jessica Pratt")
        #expect(props["album"] as? String == "On Your Own Love Again")
    }

    @Test("ExternalLinkTapped carries song_title alongside service, artist, and album")
    func externalLinkTappedCarriesSongTitle() throws {
        let event = ExternalLinkTapped(
            service: "Discogs", songTitle: "Call Your Name", artist: "Chuquimamani-Condori", album: "Edits"
        )
        let props = try #require(event.properties)

        #expect(props["song_title"] as? String == "Call Your Name")
        #expect(props["service"] as? String == "Discogs")
        #expect(props["artist"] as? String == "Chuquimamani-Condori")
        #expect(props["album"] as? String == "Edits")
    }
}
