//
//  ArtistStreamingLinksTests.swift
//  SemanticIndex
//
//  Tests for streaming link URL construction from semantic-index data.
//
//  Created by Jake Bromberg on 04/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import SemanticIndex

@Suite("ArtistStreamingLinks")
struct ArtistStreamingLinksTests {

    @Test("Constructs Spotify URL from artist ID")
    func spotifyURL() {
        let detail = SemanticIndexArtistDetail(
            id: 1,
            canonicalName: "Stereolab",
            spotifyArtistId: "abc123"
        )
        let links = ArtistStreamingLinks(detail: detail)
        #expect(links.spotifyURL == URL(string: "https://open.spotify.com/artist/abc123"))
    }

    @Test("Constructs Bandcamp URL from bandcamp ID")
    func bandcampURL() {
        let detail = SemanticIndexArtistDetail(
            id: 1,
            canonicalName: "Broadcast",
            bandcampId: "broadcast"
        )
        let links = ArtistStreamingLinks(detail: detail)
        #expect(links.bandcampURL == URL(string: "https://broadcast.bandcamp.com"))
    }

    @Test("Prefers Apple Music album URL from preview over artist page")
    func appleMusicPrefersAlbumURL() {
        let detail = SemanticIndexArtistDetail(
            id: 1,
            canonicalName: "Tortoise",
            appleMusicArtistId: "artist456"
        )
        let preview = SemanticIndexPreview(
            albumURL: URL(string: "https://music.apple.com/album/tnt/123456")
        )
        let links = ArtistStreamingLinks(detail: detail, preview: preview)
        #expect(links.appleMusicURL == URL(string: "https://music.apple.com/album/tnt/123456"))
    }

    @Test("Falls back to Apple Music artist page when preview has no album URL")
    func appleMusicFallsBackToArtistPage() {
        let detail = SemanticIndexArtistDetail(
            id: 1,
            canonicalName: "Tortoise",
            appleMusicArtistId: "artist456"
        )
        let links = ArtistStreamingLinks(detail: detail)
        #expect(links.appleMusicURL == URL(string: "https://music.apple.com/artist/artist456"))
    }

    @Test("All links nil when no streaming IDs present")
    func noStreamingIDs() {
        let detail = SemanticIndexArtistDetail(id: 1, canonicalName: "Unknown Artist")
        let links = ArtistStreamingLinks(detail: detail)
        #expect(links.appleMusicURL == nil)
        #expect(links.spotifyURL == nil)
        #expect(links.bandcampURL == nil)
        #expect(!links.hasLinks)
    }

    @Test("hasLinks returns true when at least one link is present")
    func hasLinksReturnsTrue() {
        let detail = SemanticIndexArtistDetail(
            id: 1,
            canonicalName: "Laetitia Sadier",
            spotifyArtistId: "xyz"
        )
        let links = ArtistStreamingLinks(detail: detail)
        #expect(links.hasLinks)
    }
}
