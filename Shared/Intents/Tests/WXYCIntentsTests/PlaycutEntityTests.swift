//
//  PlaycutEntityTests.swift
//  WXYCIntents
//
//  Verifies that PlaycutEntity mirrors a source Playcut's identifier and display fields
//  so downstream Spotlight and contextual-cue integrations have a stable bridge.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
import Playlist
import PlaylistTesting
@testable import WXYCIntents

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

        // DisplayRepresentation exposes its LocalizedStringResource via a public
        // property; comparing the rendered string keeps the test hermetic.
        let representation = entity.displayRepresentation
        let titleString = String(localized: representation.title)

        #expect(titleString == "Call Your Name")
    }
}
