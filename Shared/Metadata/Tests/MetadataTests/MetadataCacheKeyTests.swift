//
//  MetadataCacheKeyTests.swift
//  Metadata
//
//  Tests for MetadataCacheKey cache key generation including Discogs entity keys.
//
//  Created by Jake Bromberg on 03/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import Metadata

@Suite("MetadataCacheKey Tests")
struct MetadataCacheKeyTests {

    // MARK: - Existing Key Tests

    @Test("artist key uses discogs ID")
    func artistKeyUsesDiscogsId() {
        let key = MetadataCacheKey.artist(discogsId: 12345)
        #expect(key == "artist-12345")
    }

    @Test("album key uses artist name and release title")
    func albumKeyUsesArtistAndRelease() {
        let key = MetadataCacheKey.album(artistName: "Stereolab", releaseTitle: "Aluminum Tunes")
        #expect(key == "album-Stereolab-Aluminum Tunes")
    }

    @Test("album key uses unknown for empty release title")
    func albumKeyUsesUnknownForEmptyRelease() {
        let key = MetadataCacheKey.album(artistName: "Chuquimamani-Condori", releaseTitle: "")
        #expect(key == "album-Chuquimamani-Condori-unknown")
    }

    @Test("streaming key uses artist name and song title")
    func streamingKeyUsesArtistAndSong() {
        let key = MetadataCacheKey.streaming(artistName: "Duke Ellington & John Coltrane", songTitle: "In a Sentimental Mood")
        #expect(key == "streaming-Duke Ellington & John Coltrane-In a Sentimental Mood")
    }

    // MARK: - Discogs Entity Key Tests

    @Test("discogs entity key includes type and ID")
    func discogsEntityKeyIncludesTypeAndId() {
        let key = MetadataCacheKey.discogsEntity(type: "artist", id: 42)
        #expect(key.contains("artist"))
        #expect(key.contains("42"))
    }

    @Test("discogs entity key differs for different types")
    func discogsEntityKeyDiffersForDifferentTypes() {
        let artistKey = MetadataCacheKey.discogsEntity(type: "artist", id: 100)
        let releaseKey = MetadataCacheKey.discogsEntity(type: "release", id: 100)
        #expect(artistKey != releaseKey)
    }

    @Test("discogs entity key differs for different IDs")
    func discogsEntityKeyDiffersForDifferentIds() {
        let key1 = MetadataCacheKey.discogsEntity(type: "artist", id: 1)
        let key2 = MetadataCacheKey.discogsEntity(type: "artist", id: 2)
        #expect(key1 != key2)
    }

    @Test("discogs entity key is consistent for same inputs")
    func discogsEntityKeyIsConsistent() {
        let key1 = MetadataCacheKey.discogsEntity(type: "master", id: 999)
        let key2 = MetadataCacheKey.discogsEntity(type: "master", id: 999)
        #expect(key1 == key2)
    }
}
