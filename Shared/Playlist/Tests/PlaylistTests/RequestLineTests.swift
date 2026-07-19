//
//  RequestLineTests.swift
//  Playlist
//
//  Verifies the RequestLine presence model: how the tri-state OnAir signal maps
//  to booth availability. The say-hi affordance is a presence indicator (named
//  DJ only), and confirmed automation closes both channels — an empty booth
//  reads no requests and answers no phone. Unknown stays open because a human
//  may be on the board even when the backend isn't saying so.
//
//  Created by Jake Bromberg on 07/19/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import Playlist

@Suite("RequestLine Tests")
struct RequestLineTests {

    @Test("A named DJ opens the booth and invites conversation")
    func namedDJ() {
        let line = RequestLine(onAir: .dj("DJ HOUNDSTOOTH"))
        #expect(line.djName == "DJ HOUNDSTOOTH")
        #expect(line.boothIsOpen)
        #expect(line.invitesConversation)
    }

    @Test("Automation closes the booth: nobody reads requests or answers the phone")
    func automation() {
        let line = RequestLine(onAir: .automation)
        #expect(line.djName == nil)
        #expect(!line.boothIsOpen)
        #expect(!line.invitesConversation)
    }

    @Test("Unknown keeps the booth open but never invites — a human may be on the board")
    func unknown() {
        let line = RequestLine(onAir: .unknown)
        #expect(line.djName == nil)
        #expect(line.boothIsOpen)
        #expect(!line.invitesConversation)
    }
}
