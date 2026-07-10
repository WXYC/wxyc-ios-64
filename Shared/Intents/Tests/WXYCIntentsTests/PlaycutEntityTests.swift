//
//  PlaycutEntityTests.swift
//  WXYCIntents
//
//  Verifies that PlaycutEntity carries the fields Spotlight and Siri contextual
//  cues need (title, artist, release, artwork, label, genres, broadcast time)
//  so a tapped Spotlight result surfaces the same metadata the in-app detail
//  view does, and that the CoreSpotlight attribute set links back to the
//  entity id for OpenPlaycut routing.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
import Playlist
import PlaylistTesting
@testable import WXYCIntents
#if !os(watchOS) && !os(tvOS)
import CoreSpotlight
#endif

@Suite("PlaycutEntity")
struct PlaycutEntityTests {
    @Test("mirrors the source playcut id")
    func mirrorsSourcePlaycutID() {
        let playcut = Playcut.stub(id: 42)
        let entity = PlaycutEntity(playcut: playcut)

        #expect(entity.id.value == playcut.id)
        #expect(entity.id == PlaycutID(42))
    }

    @Test("round-trips its id through the EntityIdentifier string form")
    func roundTripsIdentifierViaString() {
        let entity = PlaycutEntity(playcut: .stub(id: 12345))
        let identifierString = entity.id.entityIdentifierString

        let decoded = PlaycutID.entityIdentifier(for: identifierString)

        #expect(decoded == entity.id)
    }

    @Test("copies displayable metadata from the source playcut")
    func copiesDisplayFields() {
        let playcut = Playcut.stub(
            id: 7,
            songTitle: "Peng!33",
            artistName: "Stereolab",
            releaseTitle: "Emperor Tomato Ketchup"
        )
        let entity = PlaycutEntity(playcut: playcut)

        #expect(entity.title == "Peng!33")
        #expect(entity.artistName == "Stereolab")
        #expect(entity.releaseTitle == "Emperor Tomato Ketchup")
    }

    @Test("carries the source playcut's artwork, label, and genres")
    func carriesRichMetadata() {
        let artwork = URL(string: "https://example.com/dj.jpg")
        let entity = PlaycutEntity(playcut: .stub(
            labelName: "Kranky",
            artworkURL: artwork,
            genres: ["Rock", "Post-punk"]
        ))

        #expect(entity.artworkURL == artwork)
        #expect(entity.labelName == "Kranky")
        #expect(entity.genres == ["Rock", "Post-punk"])
    }

    @Test("derives broadcast date from the source playcut's hour")
    func derivesBroadcastDate() {
        let hour: UInt64 = 1_700_000_000_000
        let entity = PlaycutEntity(playcut: .stub(hour: hour))

        #expect(entity.broadcastDate == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("carries a nil releaseTitle when the source has none")
    func passesThroughNilReleaseTitle() {
        let playcut = Playcut.stub(releaseTitle: nil)
        let entity = PlaycutEntity(playcut: playcut)

        #expect(entity.releaseTitle == nil)
    }

    @Test("uses the song title as the display representation title")
    func displayRepresentationUsesSongTitle() {
        let playcut = Playcut.stub(
            songTitle: "Call Your Name",
            artistName: "Chuquimamani-Condori"
        )
        let entity = PlaycutEntity(playcut: playcut)

        let representation = entity.displayRepresentation
        let titleString = String(localized: representation.title)

        #expect(titleString == "Call Your Name")
    }

    @Test("subtitle drops a trailing em-dash when the source release title is an empty string")
    func subtitleTextGuardsEmptyReleaseTitle() {
        let entity = PlaycutEntity(playcut: .stub(
            songTitle: "some track",
            artistName: "Cat Power",
            releaseTitle: ""
        ))

        #expect(entity.subtitleText == "Cat Power")
    }

    #if !os(watchOS) && !os(tvOS)
    @Test("populates the CoreSpotlight attribute set with Spotlight-visible metadata")
    func attributeSetCarriesSpotlightFields() {
        let artwork = URL(string: "https://example.com/juana.jpg")
        let entity = PlaycutEntity(playcut: .stub(
            id: 42,
            hour: 1_700_000_000_000,
            songTitle: "la paradoja",
            labelName: "Sonamos",
            artistName: "Juana Molina",
            releaseTitle: "DOGA",
            artworkURL: artwork,
            genres: ["Electronic", "Ambient"]
        ))

        let set = entity.attributeSet

        #expect(set.title == "la paradoja")
        #expect(set.artist == "Juana Molina")
        #expect(set.album == "DOGA")
        #expect(set.genre == "Electronic")
        #expect(set.thumbnailURL == artwork)
        #expect(set.contentCreationDate == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(set.relatedUniqueIdentifier == "42")
        #expect(set.keywords == ["Sonamos", "Electronic", "Ambient"])
        #expect(set.contentDescription == entity.subtitleText)
    }

    @Test("keyword array drops empty-string labelName rather than emitting a blank entry")
    func attributeSetDropsEmptyLabelName() {
        let entity = PlaycutEntity(playcut: .stub(labelName: "", genres: ["Rock"]))

        #expect(entity.attributeSet.keywords == ["Rock"])
    }
    #endif
}
