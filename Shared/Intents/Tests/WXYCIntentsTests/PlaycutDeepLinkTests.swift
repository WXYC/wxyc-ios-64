//
//  PlaycutDeepLinkTests.swift
//  WXYCIntents
//
//  Round-trip guarantees for the wxyc://playcut/<id> deep link so the encoder
//  in OpenPlaycut and the decoder in AppLifecycleModifier stay in lockstep.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import WXYCIntents

@Suite("PlaycutDeepLink")
struct PlaycutDeepLinkTests {
    @Test("encodes a playcut id into a wxyc://playcut/<id> URL")
    func encodesPlaycutID() throws {
        let url = try #require(PlaycutDeepLink.url(for: 42))

        #expect(url.scheme == "wxyc")
        #expect(url.host == "playcut")
        #expect(url.path == "/42")
    }

    @Test("decodes a playcut id from a matching URL")
    func decodesPlaycutID() throws {
        let url = try #require(URL(string: "wxyc://playcut/42"))

        #expect(PlaycutDeepLink.playcutID(from: url) == 42)
    }

    @Test("round-trips arbitrary playcut identifiers", arguments: [
        UInt64(0), 1, 42, 12345, UInt64.max
    ])
    func roundTripsIdentifiers(_ playcutID: UInt64) throws {
        let url = try #require(PlaycutDeepLink.url(for: playcutID))

        #expect(PlaycutDeepLink.playcutID(from: url) == playcutID)
    }

    @Test("rejects URLs with the wrong scheme")
    func rejectsWrongScheme() throws {
        let url = try #require(URL(string: "https://playcut/42"))

        #expect(PlaycutDeepLink.playcutID(from: url) == nil)
    }

    @Test("rejects wxyc URLs with a non-playcut host")
    func rejectsWrongHost() throws {
        let url = try #require(URL(string: "wxyc://show/42"))

        #expect(PlaycutDeepLink.playcutID(from: url) == nil)
    }

    @Test("rejects wxyc://playcut URLs with a non-numeric identifier")
    func rejectsNonNumericID() throws {
        let url = try #require(URL(string: "wxyc://playcut/not-a-number"))

        #expect(PlaycutDeepLink.playcutID(from: url) == nil)
    }
}
