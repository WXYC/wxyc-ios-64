//
//  WXYCDeepLinkTests.swift
//  WXYCIntents
//
//  Round-trip and rejection tests for the wxyc:// deep-link parser. Guards the
//  invariant that unknown hosts return nil rather than routing to any handler,
//  which is the shape AppLifecycleModifier relies on to avoid the "silent
//  playback for any wxyc:// URL" fall-through.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import WXYCIntents

@Suite("WXYCDeepLink")
struct WXYCDeepLinkTests {
    @Test("encodes a playcut id into wxyc://playcut/<id>")
    func encodesPlaycutID() throws {
        let url = try #require(WXYCDeepLink.playcut(PlaycutID(42)).url)

        #expect(url.scheme == "wxyc")
        #expect(url.host == "playcut")
        #expect(url.path == "/42")
    }

    @Test("encodes a bare wxyc://play link")
    func encodesPlay() throws {
        let url = try #require(WXYCDeepLink.play.url)

        #expect(url.scheme == "wxyc")
        #expect(url.host == "play")
        #expect(url.path == "")
    }

    @Test("parses wxyc://playcut/<id> URLs")
    func parsesPlaycutURL() throws {
        let url = try #require(URL(string: "wxyc://playcut/42"))

        #expect(WXYCDeepLink(url: url) == .playcut(PlaycutID(42)))
    }

    @Test("parses wxyc://play")
    func parsesPlayURL() throws {
        let url = try #require(URL(string: "wxyc://play"))

        #expect(WXYCDeepLink(url: url) == .play)
    }

    @Test("round-trips arbitrary playcut identifiers", arguments: [
        UInt64(0), 1, 42, 12345, UInt64.max
    ])
    func roundTripsIdentifiers(_ raw: UInt64) throws {
        let original = WXYCDeepLink.playcut(PlaycutID(raw))
        let url = try #require(original.url)

        #expect(WXYCDeepLink(url: url) == original)
    }

    @Test("accepts case-insensitive scheme and host per RFC 3986")
    func acceptsCaseInsensitiveComponents() throws {
        let variants = [
            "WXYC://playcut/42",
            "wxyc://PLAYCUT/42",
            "Wxyc://Playcut/42",
        ]
        for raw in variants {
            let url = try #require(URL(string: raw))
            #expect(WXYCDeepLink(url: url) == .playcut(PlaycutID(42)), "\(raw)")
        }
    }

    @Test("rejects URLs with the wrong scheme")
    func rejectsWrongScheme() throws {
        let url = try #require(URL(string: "https://playcut/42"))

        #expect(WXYCDeepLink(url: url) == nil)
    }

    @Test("rejects unknown hosts so unmatched wxyc:// URLs never fall through to playback")
    func rejectsUnknownHost() throws {
        for raw in ["wxyc://show/42", "wxyc://artist/42", "wxyc://bogus"] {
            let url = try #require(URL(string: raw))
            #expect(WXYCDeepLink(url: url) == nil, "\(raw)")
        }
    }

    @Test("rejects wxyc://playcut with a non-numeric identifier")
    func rejectsNonNumericPlaycutID() throws {
        for raw in [
            "wxyc://playcut/not-a-number",
            "wxyc://playcut/-1",
            "wxyc://playcut/",
        ] {
            let url = try #require(URL(string: raw))
            #expect(WXYCDeepLink(url: url) == nil, "\(raw)")
        }
    }

    @Test("rejects wxyc://playcut URLs with extra path segments")
    func rejectsExtraPathSegments() throws {
        for raw in ["wxyc://playcut/42/extra", "wxyc://playcut/42/43"] {
            let url = try #require(URL(string: raw))
            #expect(WXYCDeepLink(url: url) == nil, "\(raw)")
        }
    }

    @Test("rejects wxyc://play URLs with any path segments")
    func rejectsPlayWithPath() throws {
        for raw in ["wxyc://play/42", "wxyc://play/anything"] {
            let url = try #require(URL(string: raw))
            #expect(WXYCDeepLink(url: url) == nil, "\(raw)")
        }
    }
}
