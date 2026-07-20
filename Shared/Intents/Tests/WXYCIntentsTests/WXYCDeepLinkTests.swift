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
            "wxyc://playcut/+42",
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

    // MARK: - Concerts (#537)

    @Test("encodes a concert id into the wxyc://concert/<id> scheme alias")
    func encodesConcert() throws {
        let url = try #require(WXYCDeepLink.concert(4821).url)

        #expect(url.scheme == "wxyc")
        #expect(url.host == "concert")
        #expect(url.path == "/4821")
    }

    @Test("parses the wxyc://concert/<id> scheme alias")
    func parsesConcertSchemeAlias() throws {
        let url = try #require(URL(string: "wxyc://concert/4821"))

        #expect(WXYCDeepLink(url: url) == .concert(4821))
    }

    @Test("round-trips concert ids through the scheme alias", arguments: [0, 1, 42, 4821, 999_999])
    func roundTripsConcerts(_ id: Int) throws {
        let original = WXYCDeepLink.concert(id)
        let url = try #require(original.url)

        #expect(WXYCDeepLink(url: url) == original)
    }

    @Test("parses a bare https://wxyc.org/shows/<id> universal link")
    func parsesUniversalLinkBare() throws {
        let url = try #require(URL(string: "https://wxyc.org/shows/4821"))

        #expect(WXYCDeepLink(universalLink: url) == .concert(4821))
    }

    @Test("parses a slugged universal link, ignoring the slug")
    func parsesUniversalLinkSlugged() throws {
        let url = try #require(URL(string: "https://wxyc.org/shows/4821-jessica-pratt-at-cats-cradle"))

        #expect(WXYCDeepLink(universalLink: url) == .concert(4821))
    }

    @Test("accepts a case-insensitive scheme/host on the universal link")
    func universalLinkCaseInsensitive() throws {
        for raw in [
            "HTTPS://WXYC.ORG/shows/4821",
            "https://WXYC.org/shows/4821",
        ] {
            let url = try #require(URL(string: raw))
            #expect(WXYCDeepLink(universalLink: url) == .concert(4821), "\(raw)")
        }
    }

    @Test("rejects a universal link on the wrong host")
    func rejectsUniversalLinkWrongHost() throws {
        for raw in ["https://example.com/shows/4821", "https://wxyc.com/shows/4821"] {
            let url = try #require(URL(string: raw))
            #expect(WXYCDeepLink(universalLink: url) == nil, "\(raw)")
        }
    }

    @Test("rejects a universal link on a non-/shows path")
    func rejectsUniversalLinkWrongPath() throws {
        for raw in [
            "https://wxyc.org/artists/4821",
            "https://wxyc.org/4821",
            "https://wxyc.org/shows",
            "https://wxyc.org/shows/4821/extra",
        ] {
            let url = try #require(URL(string: raw))
            #expect(WXYCDeepLink(universalLink: url) == nil, "\(raw)")
        }
    }

    @Test("rejects a universal link whose id is not a leading integer")
    func rejectsUniversalLinkNonInteger() throws {
        for raw in [
            "https://wxyc.org/shows/jessica-pratt",
            "https://wxyc.org/shows/-1",
            "https://wxyc.org/shows/abc",
        ] {
            let url = try #require(URL(string: raw))
            #expect(WXYCDeepLink(universalLink: url) == nil, "\(raw)")
        }
    }

    @Test("rejects a non-https universal link (only https validates the AASA)")
    func rejectsUniversalLinkNonHTTPS() throws {
        for raw in ["http://wxyc.org/shows/4821", "wxyc://wxyc.org/shows/4821"] {
            let url = try #require(URL(string: raw))
            #expect(WXYCDeepLink(universalLink: url) == nil, "\(raw)")
        }
    }

    @Test("rejects a wxyc://concert alias with a non-integer id")
    func rejectsConcertSchemeNonInteger() throws {
        for raw in [
            "wxyc://concert/not-a-number",
            "wxyc://concert/-1",
            "wxyc://concert/+42",
            "wxyc://concert/",
        ] {
            let url = try #require(URL(string: raw))
            #expect(WXYCDeepLink(url: url) == nil, "\(raw)")
        }
    }

    @Test("rejects a wxyc://concert alias with extra path segments")
    func rejectsConcertSchemeExtraSegments() throws {
        for raw in ["wxyc://concert/4821/extra", "wxyc://concert/4821/48"] {
            let url = try #require(URL(string: raw))
            #expect(WXYCDeepLink(url: url) == nil, "\(raw)")
        }
    }

    @Test("the two initializers don't cross-parse each other's URL shape")
    func initializersDoNotCrossParse() throws {
        // A universal link is not a wxyc:// URL…
        let web = try #require(URL(string: "https://wxyc.org/shows/4821"))
        #expect(WXYCDeepLink(url: web) == nil)
        // …and a scheme alias is not a universal link.
        let scheme = try #require(URL(string: "wxyc://concert/4821"))
        #expect(WXYCDeepLink(universalLink: scheme) == nil)
    }
}
