//
//  PlaycutMetadataServiceV2FallbackTests.swift
//  Metadata
//
//  Tests for the V2-inline-metadata fallthrough behavior in PlaycutMetadataService.
//  When a V2 flowsheet row carries inline metadata but every streaming URL is nil,
//  the service should still issue a `/proxy/metadata/album` fetch so the BS read
//  path can fill in the streaming side. When the result still has no streaming
//  links, the cached entry must use a short TTL so that a freshly-enriched row
//  supersedes the empty entry within the same iOS session.
//
//  Created by Jake Bromberg on 05/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import Core
import Playlist
import PlaylistTesting
@testable import Caching
@testable import Metadata

@Suite("PlaycutMetadataService V2 fallback")
struct PlaycutMetadataServiceV2FallbackTests {

    // MARK: - V2 fallthrough

    @Test("Inline V2 with at least one streaming URL skips the proxy fetch")
    func inlineV2WithStreamingURLsSkipsFetch() async throws {
        // Given
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = MetadataMockWebSession()
        let service = PlaycutMetadataService(session: mockSession, cache: cache)

        let playcut = Playcut.stub(
            songTitle: "la paradoja",
            labelName: "Sonamos",
            artistName: "Juana Molina",
            releaseTitle: "DOGA"
        )
        let inline = PlaycutMetadata(
            artist: ArtistMetadata(bio: "Argentine singer-songwriter."),
            album: AlbumMetadata(label: "Sonamos", releaseYear: 2022),
            streaming: StreamingLinks(spotifyURL: URL(string: "https://open.spotify.com/track/x"))
        )

        // When
        let result = await service.fetchMetadata(for: playcut, inline: inline)

        // Then
        #expect(mockSession.requestCount == 0, "Should not call the proxy when inline streaming is present")
        #expect(result.streaming.spotifyURL?.absoluteString == "https://open.spotify.com/track/x")
        #expect(result.album.label == "Sonamos")
        #expect(result.artistBio == "Argentine singer-songwriter.")
    }

    @Test("Inline V2 with empty streaming falls through to /proxy/metadata/album")
    func inlineV2WithEmptyStreamingHitsProxy() async throws {
        // Given
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = MetadataMockWebSession()
        let service = PlaycutMetadataService(session: mockSession, cache: cache)

        let playcut = Playcut.stub(
            songTitle: "Reckoner",
            labelName: "self-released",
            artistName: "Tragic Magic",
            releaseTitle: "Tragic Magic"
        )
        // Inline V2 row has artwork + discogs but every streaming URL is nil
        let inline = PlaycutMetadata(
            artist: .empty,
            album: AlbumMetadata(label: "self-released", artworkURL: URL(string: "https://example.com/a.jpg")),
            streaming: .empty
        )

        // BS read path resolves an Apple-Music search-URL fallback
        let albumResponse = """
        {
            "discogsReleaseId": null,
            "discogsUrl": null,
            "releaseYear": null,
            "spotifyUrl": "https://open.spotify.com/search/Tragic%20Magic",
            "appleMusicUrl": "https://music.apple.com/us/search?term=Tragic%20Magic",
            "youtubeMusicUrl": null,
            "bandcampUrl": null,
            "soundcloudUrl": null
        }
        """.data(using: .utf8)!
        mockSession.responses["proxy/metadata/album"] = albumResponse

        // When
        let result = await service.fetchMetadata(for: playcut, inline: inline)

        // Then
        #expect(mockSession.requestCount >= 1, "Should hit the proxy when inline streaming is empty")
        #expect(result.streaming.spotifyURL?.absoluteString == "https://open.spotify.com/search/Tragic%20Magic")
        #expect(result.streaming.appleMusicURL?.absoluteString == "https://music.apple.com/us/search?term=Tragic%20Magic")
    }

    @Test("Inline V2 fallthrough preserves inline album and artist data when proxy omits them")
    func inlineV2FallthroughPreservesInlineData() async throws {
        // Given
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = MetadataMockWebSession()
        let service = PlaycutMetadataService(session: mockSession, cache: cache)

        let playcut = Playcut.stub(
            songTitle: "Call Your Name",
            artistName: "Chuquimamani-Condori",
            releaseTitle: "Edits"
        )
        let inline = PlaycutMetadata(
            artist: ArtistMetadata(bio: "Producer from Bolivia."),
            album: AlbumMetadata(label: "self-released", releaseYear: 2023),
            streaming: .empty
        )

        // Proxy returns ONLY streaming URLs; no album/artist enrichment
        let albumResponse = """
        {
            "discogsReleaseId": null,
            "discogsUrl": null,
            "releaseYear": null,
            "spotifyUrl": "https://open.spotify.com/search/Chuquimamani-Condori",
            "appleMusicUrl": null,
            "youtubeMusicUrl": null,
            "bandcampUrl": null,
            "soundcloudUrl": null
        }
        """.data(using: .utf8)!
        mockSession.responses["proxy/metadata/album"] = albumResponse

        // When
        let result = await service.fetchMetadata(for: playcut, inline: inline)

        // Then - inline album+artist data is preserved; proxy streaming fills the gap
        #expect(result.album.label == "self-released")
        #expect(result.album.releaseYear == 2023)
        #expect(result.artistBio == "Producer from Bolivia.")
        #expect(result.streaming.spotifyURL?.absoluteString == "https://open.spotify.com/search/Chuquimamani-Condori")
    }

    @Test("No inline V2 metadata behaves identically to fetchMetadata(for:)")
    func noInlineFallsBackToProxyFetch() async throws {
        // Given
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = MetadataMockWebSession()
        let service = PlaycutMetadataService(session: mockSession, cache: cache)

        let playcut = Playcut.stub(
            songTitle: "Back, Baby",
            labelName: "Drag City",
            artistName: "Jessica Pratt",
            releaseTitle: "On Your Own Love Again"
        )

        let albumResponse = """
        {
            "discogsReleaseId": 99999,
            "discogsUrl": null,
            "releaseYear": 2015,
            "label": "Drag City",
            "spotifyUrl": "https://open.spotify.com/track/abc",
            "appleMusicUrl": null,
            "youtubeMusicUrl": null,
            "bandcampUrl": null,
            "soundcloudUrl": null
        }
        """.data(using: .utf8)!
        mockSession.responses["proxy/metadata/album"] = albumResponse

        // When
        let result = await service.fetchMetadata(for: playcut, inline: nil)

        // Then
        #expect(mockSession.requestCount >= 1)
        #expect(result.album.releaseYear == 2015)
        #expect(result.streaming.spotifyURL?.absoluteString == "https://open.spotify.com/track/abc")
    }

    // MARK: - Short TTL on empty-streaming cache entries

    @Test("Empty streaming response is cached with the short TTL constant")
    func emptyStreamingUsesShortTTL() async throws {
        // Given
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = MetadataMockWebSession()
        let service = PlaycutMetadataService(session: mockSession, cache: cache)

        let playcut = Playcut.stub(
            songTitle: "In a Sentimental Mood",
            labelName: "Impulse Records",
            artistName: "Duke Ellington & John Coltrane",
            releaseTitle: "Duke Ellington & John Coltrane"
        )

        // Proxy returns every streaming URL as null
        let albumResponse = """
        {
            "discogsReleaseId": null,
            "discogsUrl": null,
            "releaseYear": null,
            "spotifyUrl": null,
            "appleMusicUrl": null,
            "youtubeMusicUrl": null,
            "bandcampUrl": null,
            "soundcloudUrl": null
        }
        """.data(using: .utf8)!
        mockSession.responses["proxy/metadata/album"] = albumResponse

        // When
        _ = await service.fetchMetadata(for: playcut)

        // Then - streaming cache entry uses the short TTL, NOT .sevenDays
        let streamingKey = MetadataCacheKey.streaming(
            artistName: "Duke Ellington & John Coltrane",
            songTitle: "In a Sentimental Mood"
        )
        let metadata = mockCache.metadata(for: streamingKey)
        #expect(metadata != nil, "Streaming entry should be cached")
        #expect(
            metadata?.lifespan == PlaycutMetadataService.emptyStreamingLifespan,
            "Empty-streaming entry must use emptyStreamingLifespan, not .sevenDays"
        )
        #expect(
            PlaycutMetadataService.emptyStreamingLifespan < .sevenDays,
            "Short TTL must be strictly shorter than the populated-streaming TTL"
        )
    }

    @Test("Populated streaming response keeps the seven-day TTL")
    func populatedStreamingKeepsSevenDayTTL() async throws {
        // Given
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = MetadataMockWebSession()
        let service = PlaycutMetadataService(session: mockSession, cache: cache)

        let playcut = Playcut.stub(
            songTitle: "Aluminum Tunes",
            artistName: "Stereolab",
            releaseTitle: "Aluminum Tunes"
        )

        let albumResponse = """
        {
            "discogsReleaseId": null,
            "discogsUrl": null,
            "releaseYear": null,
            "spotifyUrl": "https://open.spotify.com/track/xyz",
            "appleMusicUrl": null,
            "youtubeMusicUrl": null,
            "bandcampUrl": null,
            "soundcloudUrl": null
        }
        """.data(using: .utf8)!
        mockSession.responses["proxy/metadata/album"] = albumResponse

        // When
        _ = await service.fetchMetadata(for: playcut)

        // Then
        let streamingKey = MetadataCacheKey.streaming(
            artistName: "Stereolab",
            songTitle: "Aluminum Tunes"
        )
        let metadata = mockCache.metadata(for: streamingKey)
        #expect(metadata?.lifespan == .sevenDays, "Populated streaming should retain .sevenDays TTL")
    }
}
