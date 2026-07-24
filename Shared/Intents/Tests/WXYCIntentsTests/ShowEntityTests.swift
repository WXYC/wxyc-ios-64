//
//  ShowEntityTests.swift
//  WXYCIntents
//
//  Verifies that ShowEntity mirrors the sign-on ShowMarker's identity and
//  surfaces a minimal Siri/Spotlight-facing display representation (DJ name
//  as title, optional show message as subtitle).
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
import Playlist
import PlaylistTesting
@testable import WXYCIntents

@Suite("ShowEntity")
struct ShowEntityTests {
    @Test("mirrors the sign-on show marker's id")
    func mirrorsSignOnID() {
        let signOn = ShowMarker.stub(id: 99, djName: "Jake B")
        let entity = ShowEntity(start: signOn)

        #expect(entity.id.value == signOn.id)
        #expect(entity.id == ShowID(99))
    }

    @Test("uses the DJ name as the display title")
    func displayTitleUsesDJName() {
        let signOn = ShowMarker.stub(djName: "Jake B")
        let entity = ShowEntity(start: signOn)

        let representation = entity.displayRepresentation
        let titleString = String(localized: representation.title)

        #expect(titleString == "Jake B")
    }

    @Test("falls back to the station name when the show marker has no DJ name")
    func displayTitleFallsBackToStationName() {
        let signOn = ShowMarker.stub(djName: nil)
        let entity = ShowEntity(start: signOn)

        let representation = entity.displayRepresentation
        let titleString = String(localized: representation.title)

        #expect(titleString == "WXYC")
    }

    @Test("carries a nil subtitle when the show marker has an empty message")
    func subtitleNilForEmptyMessage() {
        let signOn = ShowMarker.stub(djName: "Jake B", message: "")
        let entity = ShowEntity(start: signOn)

        #expect(entity.subtitleText == nil)
    }

    @Test("carries the show marker's message as the subtitle")
    func subtitleUsesMessage() {
        let signOn = ShowMarker.stub(djName: "Jake B", message: "freeform on a Tuesday")
        let entity = ShowEntity(start: signOn)

        #expect(entity.subtitleText == "freeform on a Tuesday")
    }
}
