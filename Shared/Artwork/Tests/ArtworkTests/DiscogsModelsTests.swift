//
//  DiscogsModelsTests.swift
//  Artwork
//
//  Decode coverage for the Discogs.* wire models in DiscogsArtworkService.swift.
//  Discogs.Release.Label, Discogs.Release.ReleaseArtist, and Discogs.Master.ReleaseArtist
//  used to be three separately-declared {id: Int, name: String} structs (#328) — this
//  file pins Discogs.NamedEntity, the shared type that replaced them, and proves
//  Release/Master still decode identically through it.
//
//  Created by Jake Bromberg on 08/10/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Artwork

@Suite("Discogs Models")
struct DiscogsModelsTests {

    // MARK: - Discogs.NamedEntity

    @Test("NamedEntity decodes {id, name}")
    func namedEntityDecodes() throws {
        let json = """
        {"id": 42, "name": "Drag City"}
        """.data(using: .utf8)!

        let entity = try JSONDecoder().decode(Discogs.NamedEntity.self, from: json)

        #expect(entity.id == 42)
        #expect(entity.name == "Drag City")
    }

    // MARK: - Discogs.Release
    //
    // Release.labels and Release.artists used to be declared as two distinct
    // nested types (Label, ReleaseArtist) with the identical {id, name} shape.
    // Both now decode through Discogs.NamedEntity — same JSON keys, same
    // optionality, no CodingKeys on either side, so nothing about decoding
    // changes.

    @Test("Release decodes labels and artists through NamedEntity")
    func releaseDecodesLabelsAndArtists() throws {
        let json = """
        {
            "id": 1,
            "title": "On Your Own Love Again",
            "year": 2015,
            "labels": [{"id": 100, "name": "Drag City"}],
            "artists": [{"id": 200, "name": "Jessica Pratt"}],
            "uri": "/release/1"
        }
        """.data(using: .utf8)!

        let release = try JSONDecoder().decode(Discogs.Release.self, from: json)

        #expect(release.primaryLabel == "Drag City")
        #expect(release.primaryArtistId == 200)
        #expect(release.discogsWebURL?.absoluteString == "https://www.discogs.com/release/1")
    }

    @Test("Release with no labels or artists decodes with nil computed properties")
    func releaseWithNoLabelsOrArtists() throws {
        let json = """
        {
            "id": 2,
            "title": "s/t",
            "year": null,
            "labels": null,
            "artists": null,
            "uri": null
        }
        """.data(using: .utf8)!

        let release = try JSONDecoder().decode(Discogs.Release.self, from: json)

        #expect(release.primaryLabel == nil)
        #expect(release.primaryArtistId == nil)
        #expect(release.discogsWebURL == nil)
    }

    // MARK: - Discogs.Master

    @Test("Master decodes artists through NamedEntity")
    func masterDecodesArtists() throws {
        let json = """
        {
            "id": 5,
            "title": "Edits",
            "year": 2021,
            "uri": "/master/5",
            "artists": [{"id": 300, "name": "Chuquimamani-Condori"}]
        }
        """.data(using: .utf8)!

        let master = try JSONDecoder().decode(Discogs.Master.self, from: json)

        #expect(master.primaryArtistId == 300)
        #expect(master.discogsWebURL?.absoluteString == "https://www.discogs.com/master/5")
    }
}
