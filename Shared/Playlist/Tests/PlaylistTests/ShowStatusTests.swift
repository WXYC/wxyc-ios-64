//
//  ShowStatusTests.swift
//  Playlist
//
//  Tests for the touring-show ticket-availability enum. Raw values mirror
//  triangle-shows' `EventStatus` Postgres enum (on_sale/sold_out/cancelled/free).
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import Playlist

@Suite("ShowStatus")
struct ShowStatusTests {

    // MARK: - Known raw values

    @Test("Maps each known wire value to its enum case", arguments: [
        ("on_sale", ShowStatus.onSale),
        ("sold_out", ShowStatus.soldOut),
        ("cancelled", ShowStatus.cancelled),
        ("free", ShowStatus.free),
    ])
    func mapsKnownWireValues(raw: String, expected: ShowStatus) {
        #expect(ShowStatus(wire: raw) == expected)
        #expect(ShowStatus(rawValue: raw) == expected)
    }

    // MARK: - Forward-compat fallback

    @Test("Falls back to .unknown for an unrecognized wire value")
    func unknownWireValueFallsBack() {
        // A future backend status (e.g. a new "postponed") must not crash the
        // decode; it degrades to `.unknown`, mirroring OnAir's tolerant idiom.
        #expect(ShowStatus(wire: "postponed") == .unknown)
        #expect(ShowStatus(wire: "") == .unknown)
        #expect(ShowStatus(wire: "ON_SALE") == .unknown) // case-sensitive
    }

    @Test("Falls back to .unknown for a nil wire value")
    func nilWireValueFallsBack() {
        #expect(ShowStatus(wire: nil) == .unknown)
    }

    // MARK: - Codable round-trip

    @Test("Decodes each known status from a JSON string", arguments: [
        ("on_sale", ShowStatus.onSale),
        ("sold_out", ShowStatus.soldOut),
        ("cancelled", ShowStatus.cancelled),
        ("free", ShowStatus.free),
    ])
    func decodesFromJSONString(raw: String, expected: ShowStatus) throws {
        let json = Data("\"\(raw)\"".utf8)
        #expect(try JSONDecoder().decode(ShowStatus.self, from: json) == expected)
    }

    @Test("Decodes an unrecognized JSON status string as .unknown")
    func decodesUnknownJSONStringAsUnknown() throws {
        let json = Data("\"postponed\"".utf8)
        #expect(try JSONDecoder().decode(ShowStatus.self, from: json) == .unknown)
    }
}
