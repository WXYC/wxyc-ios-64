//
//  BS2105OnAirDecodingTests.swift
//  Playlist
//
//  The iOS half of the Backend-Service#2105 wire contract: the v=2
//  `recentEntries` grouped payload now carries a top-level `onAir` field, a
//  sibling of `playcuts`/`talksets`/`breakpoints`, so shipped 3.2 clients on
//  the legacy v1 path render the on-air banner instead of hiding it.
//
//  Created by Jake Bromberg on 08/11/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import CryptoKit
@testable import Playlist

/// `Playlist.init(from:)` decodes `onAir` with `decodeIfPresent(OnAir.self,
/// forKey: .onAir) ?? .unknown`, and `OnAir` has no custom `init(from:)`, so
/// the wire shape is whatever Swift's SYNTHESIZED `Codable` produces for
/// `enum OnAir { case dj(String); case automation; case unknown }` —
/// `{"dj":{"_0":name}}` for `.dj`, `{"automation":{}}` for `.automation`.
/// `_0` is the synthesized associated-value label; it is not a name a human
/// would choose, and it is the literal, unchangeable contract of a binary
/// already in the App Store.
///
/// This is a DIFFERENT shape from `/flowsheet`'s `on_air: {dj_name}` object,
/// which `FlowsheetResponseOnAirTests` covers via `FlowsheetResponse`'s own
/// custom, tolerant decoder. `Playlist.onAir` decodes `OnAir` directly off
/// the wire with no such translation layer, because both the legacy grouped
/// feed (this suite) and `FlowsheetConverter.convert(_:onAir:)` (the v2
/// feed) hand it an already-decoded `OnAir` value through the same stored
/// property.
///
/// `OnAir.swift` and `Playlist`'s `onAir` CodingKey/decode are verified
/// byte-identical between `v3.2-AppStoreSubmission4` (068a51e7d) and the
/// commit this suite runs against — `git diff 068a51e7d..HEAD --
/// Shared/Playlist/Sources/Playlist/OnAir.swift` is empty, and
/// `Playlist`'s `CodingKeys`/`init(from:)` for `onAir` are unchanged too — so
/// decoding through the checked-out `Playlist` type here is decoding through
/// the shipped 3.2 type for this field.
@Suite("BS#2105 on-air wire decoding")
struct BS2105OnAirDecodingTests {

    /// Pinned in Backend-Service
    /// `tests/unit/services/playlist-proxy-wire-golden.test.ts` as
    /// `GOLDEN_SHA256`. Must match `BS2103EnrichedDecodingTests.goldenSHA256`
    /// — both suites assert the SAME fixture file, independently, so a stale
    /// pin in either one fails loud rather than silently drifting.
    static let goldenSHA256 = "d8cc07bd3d720442cf6ea39f71d12ca641e9330e4145ac7ad6737b3708acfbb8"

    static func fixture(_ name: String, _ ext: String) throws -> URL {
        try #require(
            Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"),
            "missing fixture \(name).\(ext)"
        )
    }

    static func loadPayload() throws -> Playlist {
        try JSONDecoder().decode(Playlist.self, from: Data(contentsOf: fixture("bs2103-enriched-payload", "json")))
    }

    // MARK: - The real payload: the golden's pinned state is a human DJ live

    @Test("The golden hash matches after BS#2105's onAir field")
    func goldenHashMatches() throws {
        let data = try Data(contentsOf: Self.fixture("bs2103-enriched-payload", "json"))
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(
            digest == Self.goldenSHA256,
            """
            The golden changed. Confirm Backend-Service regenerated it deliberately, \
            re-read the expectations below against the new bytes, then update \
            goldenSHA256 here (and in BS2103EnrichedDecodingTests) and GOLDEN_SHA256 \
            in playlist-proxy-wire-golden.test.ts.
            """
        )
    }

    @Test("The golden payload's onAir decodes to the live DJ's handle")
    func goldenOnAirDecodesToDJ() throws {
        let playlist = try Self.loadPayload()

        #expect(playlist.onAir == .dj("BS2105 Probe DJ"))
        #expect(playlist.onAir.bannerTitle == "BS2105 Probe DJ")
    }

    // MARK: - The three states, by JSON shape

    /// A minimal but structurally complete v=2 grouped envelope: empty
    /// `playcuts`/`breakpoints`/`talksets` (all non-optional on `Playlist`)
    /// plus the `onAir` literal under test. `nil` omits the key entirely.
    private static func minimalPlaylistJSON(onAir: String?) -> String {
        let onAirField = onAir.map { #","onAir":\#($0)"# } ?? ""
        return #"{"playcuts":[],"breakpoints":[],"talksets":[]\#(onAirField)}"#
    }

    @Test("A named DJ decodes to .dj(name)")
    func namedDJDecodes() throws {
        let json = Self.minimalPlaylistJSON(onAir: #"{"dj":{"_0":"bill b"}}"#)

        let playlist = try JSONDecoder().decode(Playlist.self, from: Data(json.utf8))

        #expect(playlist.onAir == .dj("bill b"))
        #expect(playlist.onAir.bannerTitle == "bill b")
    }

    @Test("Confirmed automation decodes to .automation")
    func automationDecodes() throws {
        let json = Self.minimalPlaylistJSON(onAir: #"{"automation":{}}"#)

        let playlist = try JSONDecoder().decode(Playlist.self, from: Data(json.utf8))

        #expect(playlist.onAir == .automation)
        #expect(playlist.onAir.bannerTitle == "Auto DJ")
    }

    @Test("An absent onAir key decodes to .unknown, hiding the banner")
    func absentKeyDecodesToUnknown() throws {
        let json = Self.minimalPlaylistJSON(onAir: nil)

        let playlist = try JSONDecoder().decode(Playlist.self, from: Data(json.utf8))

        #expect(playlist.onAir == .unknown)
        #expect(playlist.onAir.bannerTitle == nil)
    }

    // MARK: - The counterfactual: both failure modes, pinned deliberately
    //
    // This is the whole reason the backend needs a WireOnAir type instead of
    // an ad-hoc object literal: the intuitive, "obvious" shape is fatal, and
    // it is fatal in two different ways with two different blast radii.

    /// The intuitive-but-wrong shape: snake_case `dj_name`, matching
    /// `/flowsheet`'s `on_air` object. It does NOT translate here.
    /// `decodeIfPresent` THROWS on a present-but-malformed value, and
    /// `Playlist.playcuts` is non-optional, so one bad `onAir` blanks the
    /// ENTIRE playlist, not just the banner — LOUD.
    @Test("A snake_case {dj_name} value throws and blanks the whole Playlist — loud")
    func snakeCaseShapeThrows() throws {
        let json = Self.minimalPlaylistJSON(onAir: #"{"dj_name":"bill b"}"#)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Playlist.self, from: Data(json.utf8))
        }
    }

    /// The likelier bug to ship unnoticed. `/flowsheet` distinguishes
    /// automation with a JSON `null`, and the intuitive assumption is that
    /// `decodeIfPresent` throws on an explicit `null` the same way it throws
    /// on a malformed object. It does not:
    /// `decodeIfPresent`'s default is `guard try contains(key) &&
    /// !decodeNil(forKey: key) else { return nil }`, which treats an explicit
    /// `null` exactly like an absent key. A `null` onAir therefore decodes
    /// SILENTLY to `.unknown` (banner hidden) rather than `.automation`
    /// ("Auto DJ") — QUIET, and the reason the backend must never emit `null`
    /// for confirmed automation on this endpoint; `{"automation":{}}` is the
    /// correct shape (see `automationDecodes` above).
    @Test("A JSON null does NOT throw — it silently decodes to .unknown, hiding the banner — quiet")
    func explicitNullDoesNotThrowButHidesTheBanner() throws {
        let json = Self.minimalPlaylistJSON(onAir: "null")

        let playlist = try JSONDecoder().decode(Playlist.self, from: Data(json.utf8))

        #expect(playlist.onAir == .unknown)
    }

    // MARK: - v3.1 regression: the key doesn't exist there, so it's ignored

    /// A structural stand-in for every array element in v3.1's `Playlist`
    /// decode. It reads NOTHING from its container, so it accepts any JSON
    /// value at that array position — deliberately, since what is under test
    /// here is only the top-level key handling, not v3.1's per-entry decode
    /// logic (which has its own, unrelated, shape).
    private struct V31Sink: Decodable {
        init(from decoder: Decoder) throws {}
    }

    /// v3.1's `Playlist` `CodingKeys`, copied verbatim from commit
    /// `cc123fe1c2c9441aa1cf75a060b4392329c04c59` (tag `v3.1`,
    /// `Shared/Playlist/Sources/Playlist/PlaylistEntry.swift`):
    /// `case playcuts, breakpoints, talksets, showMarkers` — no `onAir`.
    ///
    /// Reusing the CURRENT `Playcut`/`Breakpoint`/`Talkset` types here would
    /// test the wrong thing (today's shape, not v3.1's), so array elements
    /// decode into `V31Sink` instead. What this proves is exactly and only
    /// the mechanism under test: a `KeyedDecodingContainer` silently ignores
    /// a JSON key its `CodingKeys` enum doesn't declare — which is why a v3.1
    /// binary drops `onAir` rather than throwing on it or reading it.
    private struct V31PlaylistShape: Decodable {
        let playcuts: [V31Sink]
        let breakpoints: [V31Sink]
        let talksets: [V31Sink]
        let showMarkers: [V31Sink]?

        private enum CodingKeys: String, CodingKey {
            case playcuts, breakpoints, talksets, showMarkers
        }
    }

    @Test("At v3.1, the payload still decodes and onAir is simply not there to read")
    func v31IgnoresOnAirKey() throws {
        let data = try Data(contentsOf: Self.fixture("bs2103-enriched-payload", "json"))

        let shape = try JSONDecoder().decode(V31PlaylistShape.self, from: data)

        #expect(shape.playcuts.count == 14)
    }

    @Test("At v3.1, a hand-built envelope with every onAir shape still decodes with the key ignored")
    func v31IgnoresEveryOnAirShape() throws {
        for onAirLiteral in [#"{"dj":{"_0":"bill b"}}"#, #"{"automation":{}}"#, "null", #"{"dj_name":"bill b"}"#] {
            let json = Self.minimalPlaylistJSON(onAir: onAirLiteral)

            let shape = try JSONDecoder().decode(V31PlaylistShape.self, from: Data(json.utf8))

            #expect(shape.playcuts.isEmpty)
        }
    }
}
