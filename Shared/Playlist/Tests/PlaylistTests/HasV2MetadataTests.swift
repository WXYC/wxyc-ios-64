//
//  HasV2MetadataTests.swift
//  Playlist
//
//  Tests for Playcut.hasV2Metadata (#685). The predicate must be the union of
//  "any of the 12 inline enriched fields is present" and "metadataStatus is
//  terminal" — a terminal row with zero enriched fields (canonical
//  failed_no_retry) still renders inline (base-only) rather than falling
//  through to the /proxy/metadata/album path.
//
//  Created by Jake Bromberg on 07/27/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Playlist

@Suite("Playcut.hasV2Metadata Tests")
struct HasV2MetadataTests {

    private func playcut(
        artworkURL: URL? = nil,
        discogsURL: URL? = nil,
        releaseYear: Int? = nil,
        spotifyURL: URL? = nil,
        appleMusicURL: URL? = nil,
        youtubeMusicURL: URL? = nil,
        bandcampURL: URL? = nil,
        soundcloudURL: URL? = nil,
        artistBio: String? = nil,
        artistWikipediaURL: URL? = nil,
        genres: [String]? = nil,
        styles: [String]? = nil,
        metadataStatus: MetadataStatus? = nil
    ) -> Playcut {
        Playcut(
            id: 685,
            hour: 1000,
            chronOrderID: 685,
            timeCreated: 1000,
            songTitle: "la paradoja",
            labelName: "Sonamos",
            artistName: "Juana Molina",
            releaseTitle: "DOGA",
            artworkURL: artworkURL,
            discogsURL: discogsURL,
            releaseYear: releaseYear,
            spotifyURL: spotifyURL,
            appleMusicURL: appleMusicURL,
            youtubeMusicURL: youtubeMusicURL,
            bandcampURL: bandcampURL,
            soundcloudURL: soundcloudURL,
            artistBio: artistBio,
            artistWikipediaURL: artistWikipediaURL,
            genres: genres,
            styles: styles,
            metadataStatus: metadataStatus
        )
    }

    // MARK: - Any-field-alone (non-terminal / nil status)

    @Test("nil status, no inline fields is false")
    func nilStatusNoFieldsIsFalse() {
        #expect(playcut().hasV2Metadata == false)
    }

    @Test(
        "nil status, exactly one of the 12 inline fields is true",
        arguments: [
            "artworkURL", "discogsURL", "releaseYear", "spotifyURL", "appleMusicURL",
            "youtubeMusicURL", "bandcampURL", "soundcloudURL", "artistBio",
            "artistWikipediaURL", "genres", "styles",
        ]
    )
    func nilStatusSingleFieldIsTrue(field: String) {
        let url = URL(string: "https://example.com")!
        let p: Playcut
        switch field {
        case "artworkURL": p = playcut(artworkURL: url)
        case "discogsURL": p = playcut(discogsURL: url)
        case "releaseYear": p = playcut(releaseYear: 2022)
        case "spotifyURL": p = playcut(spotifyURL: url)
        case "appleMusicURL": p = playcut(appleMusicURL: url)
        case "youtubeMusicURL": p = playcut(youtubeMusicURL: url)
        case "bandcampURL": p = playcut(bandcampURL: url)
        case "soundcloudURL": p = playcut(soundcloudURL: url)
        case "artistBio": p = playcut(artistBio: "Argentine singer-songwriter.")
        case "artistWikipediaURL": p = playcut(artistWikipediaURL: url)
        case "genres": p = playcut(genres: ["Rock"])
        case "styles": p = playcut(styles: ["Folk, World, & Country"])
        default: fatalError("unhandled field \(field)")
        }
        #expect(p.hasV2Metadata == true)
    }

    @Test("nil status, empty (non-nil) genres/styles arrays are false")
    func nilStatusEmptyArraysAreFalse() {
        #expect(playcut(genres: []).hasV2Metadata == false)
        #expect(playcut(styles: []).hasV2Metadata == false)
    }

    // MARK: - Terminal-alone (zero enriched fields)

    @Test(
        "terminal status with zero enriched fields is true",
        arguments: [MetadataStatus.enrichedMatch, .enrichedNoMatch, .failedNoRetry]
    )
    func terminalStatusZeroFieldsIsTrue(status: MetadataStatus) {
        #expect(playcut(metadataStatus: status).hasV2Metadata == true)
    }

    // MARK: - Non-terminal status regression (pending/enriching with no fields)

    @Test(
        "non-terminal status with zero enriched fields is false",
        arguments: [MetadataStatus.pending, .enriching]
    )
    func nonTerminalStatusZeroFieldsIsFalse(status: MetadataStatus) {
        #expect(playcut(metadataStatus: status).hasV2Metadata == false)
    }

    // MARK: - Union: terminal status + sparse fields still true

    @Test("terminal status with a single non-streaming field (genres only) is true")
    func terminalStatusGenresOnlyIsTrue() {
        #expect(playcut(genres: ["Rock"], metadataStatus: .failedNoRetry).hasV2Metadata == true)
    }
}
