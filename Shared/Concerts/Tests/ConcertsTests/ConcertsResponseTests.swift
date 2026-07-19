//
//  ConcertsResponseTests.swift
//  Concerts
//
//  Decodes a captured, realistic `GET /concerts` response so the hand-written
//  DTO can't silently drift from the wire. `Concert`/`Venue`/`ConcertsResponse`
//  are hand-written (not codegen'd from `wxyc-shared/api.yaml`) because the iOS
//  build does not yet consume the spec's generated Swift types; this fixture
//  test is the guard the issue asks for against that drift.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import Concerts

@Suite("ConcertsResponse")
struct ConcertsResponseTests {

    private static func fixtureData() throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: "concerts-response", withExtension: "json", subdirectory: "Fixtures")
        )
        return try Data(contentsOf: url)
    }

    @Test("Decodes a captured GET /concerts response envelope")
    func decodesCapturedResponse() throws {
        let response = try JSONDecoder().decode(ConcertsResponse.self, from: Self.fixtureData())

        #expect(response.concerts.count == 2)
        #expect(response.pagination.page == 1)
        #expect(response.pagination.limit == 50)
        #expect(response.pagination.total == 2)
        #expect(response.pagination.hasMore == false)
    }

    @Test("Decodes the full first concert with its embedded venue")
    func decodesFirstConcert() throws {
        let response = try JSONDecoder().decode(ConcertsResponse.self, from: Self.fixtureData())
        let first = try #require(response.concerts.first)

        #expect(first.id == 4821)
        #expect(first.venue.slug == "cats-cradle")
        #expect(first.venue.name == "Cat's Cradle")
        #expect(first.headliningArtistRaw == "Jessica Pratt")
        #expect(first.headliningArtistId == 512)
        #expect(first.supportingArtistsRaw == ["Julie Byrne"])
        #expect(first.status == .onSale)
        #expect(first.ticketURL == URL(string: "https://www.etix.com/ticket/p/jessica-pratt"))
        #expect(first.eventURL == URL(string: "https://catscradle.com/event/jessica-pratt"))
        #expect(first.startsAt != nil)
        #expect(first.doorsAt != nil)
        // Resolved headliner → enrichment-populated affinity neighbors survive
        // the envelope decode, ordered by weight descending (WXYC/wxyc-ios-64#493).
        #expect(first.similarArtists == [
            SimilarArtist(artistId: 231, weight: 0.94),
            SimilarArtist(artistId: 347, weight: 0.71),
        ])
    }

    @Test("Decodes the date-only second concert, tolerating null instants and empty support")
    func decodesDateOnlyConcert() throws {
        let response = try JSONDecoder().decode(ConcertsResponse.self, from: Self.fixtureData())
        let second = response.concerts[1]

        #expect(second.id == 4822)
        #expect(second.venue.address == nil)
        #expect(second.title == "Edits Release Night")
        #expect(second.headliningArtistId == nil)
        #expect(second.supportingArtistsRaw == [])
        #expect(second.startsAt == nil)
        #expect(second.doorsAt == nil)
        #expect(second.ticketURL == nil)
        #expect(second.eventURL == nil)
        // Unresolved headliner (null id) → the backend omits similar_artists, so
        // it decodes to nil rather than [] (the null-when-unresolved contract).
        #expect(second.similarArtists == nil)
        #expect(second.status == .soldOut)
    }
}
