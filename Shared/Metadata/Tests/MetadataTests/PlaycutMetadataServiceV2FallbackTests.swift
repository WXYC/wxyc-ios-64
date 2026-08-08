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
//  #761: `PlaycutMetadataService` dropped its dual `WebSession`/`URLSession`
//  fields in favor of a single `Core.WXYCProxyClient`. This file now injects
//  `MetadataV2MockWebSession` — its own stub-`URLProtocol`-backed double,
//  distinct from `PlaycutMetadataServiceCachingTests.swift`'s
//  `MetadataMockWebSession` — via the service's `urlSession:` parameter.
//  Each double's state is `static` (URLProtocol registration is by class),
//  so it's kept file-scoped and this suite carries `.serialized`: two
//  `@Suite`s sharing one such class would race even if both were serialized
//  individually, since traits only serialize *within* a suite (see
//  `CoreTesting.QueuedStubURLProtocol`'s header doc).
//

import Testing
import Foundation
import os
import Core
import Playlist
import PlaylistTesting
@testable import Caching
@testable import Metadata

// MARK: - Mock WebSession for this file's suite

/// See `PlaycutMetadataServiceCachingTests.swift`'s `MetadataMockWebSession`
/// for the design rationale — this is the same shape, kept as a separate
/// type so this suite's `.serialized` trait doesn't have to share static
/// state with that other suite's.
final class MetadataV2MockWebSession: @unchecked Sendable {
    private struct State {
        var responses: [String: Data] = [:]
        var requestedURLs: [URL] = []
        var requestCount = 0
    }

    private final class StubProtocol: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let url = request.url else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }

            let matchedData: Data? = MetadataV2MockWebSession.lock.withLock { state in
                state.requestCount += 1
                state.requestedURLs.append(url)
                let urlString = url.absoluteString
                return state.responses.first { urlString.contains($0.key) }?.value
            }

            guard let matchedData, let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
                return
            }

            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: matchedData)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private static let lock = OSAllocatedUnfairLock(initialState: State())

    /// The `URLSession` to inject as `PlaycutMetadataService`'s `urlSession`.
    let urlSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: config)
    }()

    var responses: [String: Data] {
        get { Self.lock.withLock { $0.responses } }
        set { Self.lock.withLock { $0.responses = newValue } }
    }

    var requestedURLs: [URL] { Self.lock.withLock { $0.requestedURLs } }
    var requestCount: Int { Self.lock.withLock { $0.requestCount } }

    init() {
        reset()
    }

    func reset() {
        Self.lock.withLock { $0 = State() }
    }
}

@Suite("PlaycutMetadataService V2 fallback", .serialized)
struct PlaycutMetadataServiceV2FallbackTests {

    // MARK: - V2 fallthrough

    @Test("Inline V2 with at least one streaming URL skips the proxy fetch")
    func inlineV2WithStreamingURLsSkipsFetch() async throws {
        // Given
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = MetadataV2MockWebSession()
        let service = PlaycutMetadataService(urlSession: mockSession.urlSession, cache: cache)

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

    @Test("Inline V2 genres/styles ride through the short-circuit without a proxy fetch")
    func inlineV2GenresStylesRideThroughShortCircuit() async throws {
        // Mirrors PlaycutMetadataResolver.inlineMetadata(for:)'s construction:
        // a V2 playcut carrying genres/styles plus at least one streaming URL.
        // The service must return the inline metadata verbatim (genres/styles
        // intact) and never touch the proxy (#402). This asserts the service
        // boundary specifically; the builder itself is covered directly in
        // PlaycutMetadataResolverTests.
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = MetadataV2MockWebSession()
        let service = PlaycutMetadataService(urlSession: mockSession.urlSession, cache: cache)

        let playcut = Playcut.stub(
            songTitle: "la paradoja",
            labelName: "Sonamos",
            artistName: "Juana Molina",
            releaseTitle: "DOGA",
            genres: ["Rock"],
            styles: ["Folk, World, & Country"]
        )
        // Same construction PlaycutMetadataResolver.inlineMetadata(for:)
        // performs for an inline V2 row, including the genres/styles threaded
        // through #402.
        let inline = PlaycutMetadata(
            artist: ArtistMetadata(bio: playcut.artistBio, wikipediaURL: playcut.artistWikipediaURL),
            album: AlbumMetadata(
                label: playcut.labelName,
                releaseYear: playcut.releaseYear,
                discogsURL: playcut.discogsURL,
                genres: playcut.genres,
                styles: playcut.styles
            ),
            streaming: StreamingLinks(spotifyURL: URL(string: "https://open.spotify.com/track/x"))
        )

        // When
        let result = await service.fetchMetadata(for: playcut, inline: inline)

        // Then — genres/styles survive and the short-circuit skips the proxy
        #expect(mockSession.requestCount == 0, "Inline streaming should still skip the proxy fetch")
        #expect(result.album.genres == ["Rock"])
        #expect(result.album.styles == ["Folk, World, & Country"])
        #expect(result.hasMetadataSectionContent, "genres/styles should make the metadata section render")
    }

    @Test("Inline V2 with empty streaming falls through to /proxy/metadata/album")
    func inlineV2WithEmptyStreamingHitsProxy() async throws {
        // Given
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = MetadataV2MockWebSession()
        let service = PlaycutMetadataService(urlSession: mockSession.urlSession, cache: cache)

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
        let mockSession = MetadataV2MockWebSession()
        let service = PlaycutMetadataService(urlSession: mockSession.urlSession, cache: cache)

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

    @Test("Inline V2 fallthrough preserves inline discogsUnavailable when the proxy response can't carry it (#390)")
    func inlineV2FallthroughPreservesDiscogsUnavailable() async throws {
        // Given — an inline row the MD has flagged "Not on Discogs", with
        // empty streaming so the service still falls through to the proxy
        // (Tragic Magic shape). The proxy response below is a real
        // /proxy/metadata/album payload shape; it cannot carry
        // discogsUnavailable today (WXYCAPIModels.AlbumMetadataResponse
        // doesn't declare the field — see the NOTE in
        // PlaycutMetadataService.fetchAlbumAndStreaming), so the merge must
        // fall back to the inline value rather than silently dropping it.
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = MetadataV2MockWebSession()
        let service = PlaycutMetadataService(urlSession: mockSession.urlSession, cache: cache)

        let playcut = Playcut.stub(
            songTitle: "Reckoner",
            labelName: "self-released",
            artistName: "Tragic Magic",
            releaseTitle: "Tragic Magic"
        )
        let inline = PlaycutMetadata(
            artist: .empty,
            album: AlbumMetadata(label: "self-released", discogsUnavailable: true, discogsUnavailableNote: "embargo"),
            streaming: .empty
        )

        let albumResponse = """
        {
            "discogsReleaseId": null,
            "discogsUrl": null,
            "releaseYear": null,
            "spotifyUrl": "https://open.spotify.com/search/Tragic%20Magic",
            "appleMusicUrl": null,
            "youtubeMusicUrl": null,
            "bandcampUrl": null,
            "soundcloudUrl": null
        }
        """.data(using: .utf8)!
        mockSession.responses["proxy/metadata/album"] = albumResponse

        // When
        let result = await service.fetchMetadata(for: playcut, inline: inline)

        // Then — the flag and note survive the merge, and the proxy streaming
        // URL still fills the gap the inline row left empty.
        #expect(result.album.isDiscogsUnavailable == true)
        #expect(result.album.discogsUnavailableNote == "embargo")
        #expect(result.streaming.spotifyURL?.absoluteString == "https://open.spotify.com/search/Tragic%20Magic")
    }

    @Test("Proxy discogsUnavailable now decodes and overrides inline when present (#731)")
    func proxyDiscogsUnavailableFlowsIntoMergedMetadata() async throws {
        // Given — an inline row where the MD flag is NOT set, but the BS read
        // path (BS#1901) now emits discogsUnavailable/discogsUnavailableNote on
        // /proxy/metadata/album and WXYCAPIModels.AlbumMetadataResponse
        // declares the field (#731), so it's no longer silently dropped at
        // decode time. Empty inline streaming (Tragic Magic shape) so the
        // service still falls through to the proxy.
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = MetadataV2MockWebSession()
        let service = PlaycutMetadataService(urlSession: mockSession.urlSession, cache: cache)

        let playcut = Playcut.stub(
            songTitle: "Reckoner",
            labelName: "self-released",
            artistName: "Tragic Magic",
            releaseTitle: "Tragic Magic"
        )
        let inline = PlaycutMetadata(
            artist: .empty,
            album: AlbumMetadata(label: "self-released", discogsUnavailable: false),
            streaming: .empty
        )

        let albumResponse = """
        {
            "discogsReleaseId": null,
            "discogsUrl": null,
            "releaseYear": null,
            "spotifyUrl": "https://open.spotify.com/search/Tragic%20Magic",
            "appleMusicUrl": null,
            "youtubeMusicUrl": null,
            "bandcampUrl": null,
            "soundcloudUrl": null,
            "discogsUnavailable": true,
            "discogsUnavailableNote": "embargoed promo"
        }
        """.data(using: .utf8)!
        mockSession.responses["proxy/metadata/album"] = albumResponse

        // When
        let result = await service.fetchMetadata(for: playcut, inline: inline)

        // Then — the proxy's discogsUnavailable wins over the inline `false`,
        // proving the merge (`proxy.discogsUnavailable ?? inline.discogsUnavailable`)
        // is actually fed a real decoded value now, not always nil.
        #expect(result.album.isDiscogsUnavailable == true)
        #expect(result.album.discogsUnavailableNote == "embargoed promo")
    }

    // MARK: - Non-terminal sparse-field rows reach the merge path (#685 follow-up)

    @Test("Non-terminal row with only genres inline (no streaming, no other fields) merges inline genres when the proxy omits them")
    func nonTerminalGenresOnlyRowMergesInlineGenres() async throws {
        // #685 widened hasV2Metadata to 12 fields unconditionally on
        // metadataStatus, so the resolver now builds a non-nil `inline`
        // for a pending/enriching row carrying only genres — where before,
        // hasV2Metadata (artwork/discogs/spotify only) would have been false
        // and `inline` would have been nil. That routes fetchMetadata through
        // the coalescing branch (AlbumMetadata.coalescing(over:)) instead of the old pure-proxy
        // early-return, so this row's inline genres now survive a proxy
        // response that doesn't return genres itself. Locking in that this is
        // the actual, intended behavior (proxy wins when present, inline is a
        // fallback), not an untested accident.
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = MetadataV2MockWebSession()
        let service = PlaycutMetadataService(urlSession: mockSession.urlSession, cache: cache)

        let playcut = Playcut.stub(
            songTitle: "Call Your Name",
            artistName: "Chuquimamani-Condori",
            releaseTitle: "Edits",
            genres: ["Electronic"]
            // metadataStatus defaults to nil (non-terminal)
        )
        let inline = PlaycutMetadata(
            artist: .empty,
            album: AlbumMetadata(genres: ["Electronic"]),
            streaming: .empty
        )

        // Proxy resolves streaming but says nothing about genres
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

        // Then — proxy fetch happened (this row is non-terminal with no inline
        // streaming), and the merge path preserved the inline genres the
        // proxy didn't supply
        #expect(mockSession.requestCount >= 1, "Non-terminal sparse row must still hit the proxy")
        #expect(result.album.genres == ["Electronic"], "Inline genres should survive when the proxy omits them")
        #expect(result.streaming.spotifyURL?.absoluteString == "https://open.spotify.com/search/Chuquimamani-Condori")
    }

    // MARK: - Terminal-row short-circuit (#685 Gate 2)

    @Test("Terminal row with genres-only inline metadata (no streaming) never hits the proxy")
    func terminalGenresOnlyRowSkipsProxy() async throws {
        // Load-bearing regression for #685 Gate 2: a Gate-1-only fix (hasV2Metadata
        // alone) still lets this row reach fetchMetadata with empty inline.streaming,
        // and the old Gate-2 check (`inline.streaming.hasAny`) would fall through to
        // the proxy anyway. The terminal status must short-circuit here too.
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = MetadataV2MockWebSession()
        let service = PlaycutMetadataService(urlSession: mockSession.urlSession, cache: cache)

        let playcut = Playcut(
            id: 685,
            hour: 1000,
            chronOrderID: 685,
            timeCreated: 1000,
            songTitle: "la paradoja",
            labelName: "Sonamos",
            artistName: "Juana Molina",
            releaseTitle: "DOGA",
            genres: ["Rock"],
            metadataStatus: .failedNoRetry
        )
        let inline = PlaycutMetadata(
            artist: .empty,
            album: AlbumMetadata(label: "Sonamos", genres: ["Rock"]),
            streaming: .empty
        )

        // When
        let result = await service.fetchMetadata(for: playcut, inline: inline)

        // Then
        #expect(mockSession.requestCount == 0, "Terminal row must short-circuit even with empty streaming")
        #expect(result.album.genres == ["Rock"])
    }

    @Test(
        "Terminal row carrying only one non-streaming field skips the proxy",
        arguments: [
            "appleMusicURL", "youtubeMusicURL", "bandcampURL", "soundcloudURL",
            "releaseYear", "genres", "styles", "artistBio",
        ]
    )
    func terminalRowSingleNonStreamingFieldSkipsProxy(field: String) async throws {
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = MetadataV2MockWebSession()
        let service = PlaycutMetadataService(urlSession: mockSession.urlSession, cache: cache)
        let url = URL(string: "https://example.com")!

        let playcut: Playcut
        let inline: PlaycutMetadata
        switch field {
        case "appleMusicURL":
            playcut = Playcut(id: 685, hour: 1000, chronOrderID: 685, timeCreated: 1000, songTitle: "s", labelName: nil, artistName: "a", releaseTitle: "r", appleMusicURL: url, metadataStatus: .failedNoRetry)
            inline = PlaycutMetadata(artist: .empty, album: .empty, streaming: StreamingLinks(appleMusicURL: url))
        case "youtubeMusicURL":
            playcut = Playcut(id: 685, hour: 1000, chronOrderID: 685, timeCreated: 1000, songTitle: "s", labelName: nil, artistName: "a", releaseTitle: "r", youtubeMusicURL: url, metadataStatus: .failedNoRetry)
            inline = PlaycutMetadata(artist: .empty, album: .empty, streaming: StreamingLinks(youtubeMusicURL: url))
        case "bandcampURL":
            playcut = Playcut(id: 685, hour: 1000, chronOrderID: 685, timeCreated: 1000, songTitle: "s", labelName: nil, artistName: "a", releaseTitle: "r", bandcampURL: url, metadataStatus: .failedNoRetry)
            inline = PlaycutMetadata(artist: .empty, album: .empty, streaming: StreamingLinks(bandcampURL: url))
        case "soundcloudURL":
            playcut = Playcut(id: 685, hour: 1000, chronOrderID: 685, timeCreated: 1000, songTitle: "s", labelName: nil, artistName: "a", releaseTitle: "r", soundcloudURL: url, metadataStatus: .failedNoRetry)
            inline = PlaycutMetadata(artist: .empty, album: .empty, streaming: StreamingLinks(soundcloudURL: url))
        case "releaseYear":
            playcut = Playcut(id: 685, hour: 1000, chronOrderID: 685, timeCreated: 1000, songTitle: "s", labelName: nil, artistName: "a", releaseTitle: "r", releaseYear: 2022, metadataStatus: .failedNoRetry)
            inline = PlaycutMetadata(artist: .empty, album: AlbumMetadata(releaseYear: 2022), streaming: .empty)
        case "genres":
            playcut = Playcut(id: 685, hour: 1000, chronOrderID: 685, timeCreated: 1000, songTitle: "s", labelName: nil, artistName: "a", releaseTitle: "r", genres: ["Rock"], metadataStatus: .failedNoRetry)
            inline = PlaycutMetadata(artist: .empty, album: AlbumMetadata(genres: ["Rock"]), streaming: .empty)
        case "styles":
            playcut = Playcut(id: 685, hour: 1000, chronOrderID: 685, timeCreated: 1000, songTitle: "s", labelName: nil, artistName: "a", releaseTitle: "r", styles: ["Folk"], metadataStatus: .failedNoRetry)
            inline = PlaycutMetadata(artist: .empty, album: AlbumMetadata(styles: ["Folk"]), streaming: .empty)
        case "artistBio":
            playcut = Playcut(id: 685, hour: 1000, chronOrderID: 685, timeCreated: 1000, songTitle: "s", labelName: nil, artistName: "a", releaseTitle: "r", artistBio: "Bio.", metadataStatus: .failedNoRetry)
            inline = PlaycutMetadata(artist: ArtistMetadata(bio: "Bio."), album: .empty, streaming: .empty)
        default:
            fatalError("unhandled field \(field)")
        }

        let result = await service.fetchMetadata(for: playcut, inline: inline)

        #expect(mockSession.requestCount == 0, "Terminal row with only \(field) must not hit the proxy")
        #expect(result == inline)
    }

    @Test("Terminal row with inline critic reviews returns them with zero proxy fetches (#695)")
    func terminalRowWithInlineCriticReviewsSkipsProxy() async throws {
        // Load-bearing for #695: a terminal row whose V2 flowsheet feed carried
        // critic_reviews must render ReviewsSection from feed data alone —
        // the review must survive `fetchMetadata`'s terminal short-circuit
        // (#685/#691, unmodified by this change) with no proxy round-trip.
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = MetadataV2MockWebSession()
        let service = PlaycutMetadataService(urlSession: mockSession.urlSession, cache: cache)

        let review = CriticReview(
            source: "The Quietus",
            url: URL(string: "https://thequietus.com/articles/juana-molina-doga")!,
            snippet: "A restless, shape-shifting record that never settles.",
            author: "Jane Critic",
            publishedDate: "2024-03-15",
            rating: "8.0"
        )
        let playcut = Playcut.stub(
            songTitle: "la paradoja",
            labelName: "Sonamos",
            artistName: "Juana Molina",
            releaseTitle: "DOGA",
            criticReviews: [review],
            metadataStatus: .enrichedMatch
        )
        // Same construction PlaycutMetadataResolver.inlineMetadata(for:)
        // performs for an inline V2 row, including criticReviews threaded
        // through #695.
        let inline = PlaycutMetadata(
            artist: .empty,
            album: AlbumMetadata(label: "Sonamos", criticReviews: [review]),
            streaming: .empty
        )

        // When
        let result = await service.fetchMetadata(for: playcut, inline: inline)

        // Then
        #expect(mockSession.requestCount == 0, "Terminal row must short-circuit even with reviews present")
        #expect(result.album.criticReviews == [review])
        #expect(result.album.hasCriticReviews == true)
    }

    @Test("Terminal row with zero enriched fields renders base-only, no proxy")
    func terminalEmptyRowSkipsProxy() async throws {
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = MetadataV2MockWebSession()
        let service = PlaycutMetadataService(urlSession: mockSession.urlSession, cache: cache)

        let playcut = Playcut(
            id: 685,
            hour: 1000,
            chronOrderID: 685,
            timeCreated: 1000,
            songTitle: "la paradoja",
            labelName: "Sonamos",
            artistName: "Juana Molina",
            releaseTitle: "DOGA",
            metadataStatus: .failedNoRetry
        )
        let inline = PlaycutMetadata(artist: .empty, album: .empty, streaming: .empty)

        // When
        let result = await service.fetchMetadata(for: playcut, inline: inline)

        // Then
        #expect(mockSession.requestCount == 0)
        #expect(result.streaming.hasAny == false)
    }

    @Test("No inline V2 metadata behaves identically to fetchMetadata(for:)")
    func noInlineFallsBackToProxyFetch() async throws {
        // Given
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = MetadataV2MockWebSession()
        let service = PlaycutMetadataService(urlSession: mockSession.urlSession, cache: cache)

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
        let mockSession = MetadataV2MockWebSession()
        let service = PlaycutMetadataService(urlSession: mockSession.urlSession, cache: cache)

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

    // MARK: - Artist-side fallthrough

    @Test("A bio-less proxy artist does not discard the inline V2 artist bio")
    func proxyArtistWithoutBioKeepsInlineArtistFields() async throws {
        // The album lookup resolving a `discogsArtistId` is enough to make the
        // artist fetch produce a non-empty `ArtistMetadata` — that id is written
        // into the record unconditionally (`apiResult.discogsArtistId ?? artistId`).
        // So a whole-record "is it empty?" test can never choose the inline side
        // once the album carried an artist id, and a proxy answer with no bio
        // silently replaces the bio the V2 row already had. The album side next
        // to it coalesces field-by-field; the artist side has to as well.
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = MetadataV2MockWebSession()
        let service = PlaycutMetadataService(urlSession: mockSession.urlSession, cache: cache)

        let playcut = Playcut.stub(
            songTitle: "Call Your Name",
            labelName: "self-released",
            artistName: "Chuquimamani-Condori",
            releaseTitle: "Edits",
            metadataStatus: .enriching
        )
        let inline = PlaycutMetadata(
            artist: ArtistMetadata(
                bio: "Producer from Bolivia.",
                wikipediaURL: URL(string: "https://en.wikipedia.org/wiki/Chuquimamani-Condori")
            ),
            album: AlbumMetadata(label: "self-released"),
            streaming: .empty
        )

        mockSession.responses["proxy/metadata/album"] = """
        {
            "discogsArtistId": 4242,
            "discogsUrl": null,
            "releaseYear": null,
            "spotifyUrl": "https://open.spotify.com/track/edits",
            "appleMusicUrl": null,
            "youtubeMusicUrl": null,
            "bandcampUrl": null,
            "soundcloudUrl": null
        }
        """.data(using: .utf8)!
        mockSession.responses["proxy/metadata/artist"] = """
        {
            "discogsArtistId": 4242,
            "bio": null,
            "wikipediaUrl": null,
            "imageUrl": null,
            "bioTokens": null
        }
        """.data(using: .utf8)!

        // When
        let result = await service.fetchMetadata(for: playcut, inline: inline)

        // Then
        #expect(result.artistBio == "Producer from Bolivia.", "The proxy's silence must not erase the inline bio")
        #expect(result.wikipediaURL?.absoluteString == "https://en.wikipedia.org/wiki/Chuquimamani-Condori")
        #expect(result.artist.discogsArtistId == 4242, "The proxy still contributes what only it resolved")
    }

    // MARK: - Short TTL on sparse-album cache entries (#812)

    @Test("A sparse album response is cached with the short TTL constant, not seven days")
    func sparseAlbumUsesShortTTL() async throws {
        // Given — the row is mid-enrichment, so the proxy has nothing but the
        // base label column to give back. Pinning that for a week is what made
        // #812 survive closing and reopening the card.
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = MetadataV2MockWebSession()
        let service = PlaycutMetadataService(urlSession: mockSession.urlSession, cache: cache)

        let playcut = Playcut.stub(
            songTitle: "Crawl",
            labelName: "Houndstooth",
            artistName: "Djrum",
            releaseTitle: "Meaning's Edge",
            metadataStatus: .enriching
        )

        // The production payload shape, not a minimal one: `discogs_unavailable`
        // is `NOT NULL DEFAULT false` on `library`, and the proxy assigns it for
        // every row that resolved to a catalog album, so `false` rides along on
        // the otherwise-empty pre-enrichment response. A stub that omitted it
        // would pass against a gate that keys on the field's presence — which is
        // exactly how that gate stayed inert in production.
        let albumResponse = """
        {
            "discogsReleaseId": null,
            "discogsUrl": null,
            "releaseYear": null,
            "artworkUrl": null,
            "discogsUnavailable": false,
            "spotifyUrl": "https://open.spotify.com/track/crawl",
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
        let albumKey = MetadataCacheKey.album(artistName: "Djrum", releaseTitle: "Meaning's Edge")
        let metadata = mockCache.metadata(for: albumKey)
        #expect(metadata != nil, "Album entry should be cached")
        #expect(
            metadata?.lifespan == PlaycutMetadataService.sparseAlbumLifespan,
            "Sparse album entry must use sparseAlbumLifespan, not .sevenDays"
        )
        #expect(
            PlaycutMetadataService.sparseAlbumLifespan < .sevenDays,
            "Short TTL must be strictly shorter than the enriched-album TTL"
        )
    }

    @Test(
        "A sparse album keeps the seven-day TTL when the row is not mid-enrichment",
        arguments: [MetadataStatus?.none, .enrichedNoMatch]
    )
    func sparseAlbumOutsideTheEnrichmentWindowKeepsSevenDayTTL(status: MetadataStatus?) async throws {
        // The short TTL exists for one population: a row the feed is serving
        // while Backend is still enriching it, where the sparse answer is known
        // to be temporary. A free-text play that never linked to a catalog album
        // produces the same sparse shape permanently — LML has nothing to match
        // — so short-TTLing it would re-issue the proxy round-trip on every card
        // open forever and return the same nothing each time. `nil` covers that
        // cohort along with v1 rows; a terminal status covers a row Backend has
        // already given up on.
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = MetadataV2MockWebSession()
        let service = PlaycutMetadataService(urlSession: mockSession.urlSession, cache: cache)

        let playcut = Playcut.stub(
            songTitle: "Sisters",
            labelName: nil,
            artistName: "Csillagrablók",
            releaseTitle: "Nem Latszik Semmi",
            metadataStatus: status
        )

        let albumResponse = """
        {
            "discogsReleaseId": null,
            "discogsUrl": null,
            "releaseYear": null,
            "artworkUrl": null,
            "spotifyUrl": null,
            "appleMusicUrl": null,
            "youtubeMusicUrl": null,
            "bandcampUrl": null,
            "soundcloudUrl": null
        }
        """.data(using: .utf8)!
        mockSession.responses["proxy/metadata/album"] = albumResponse

        // `fetchMetadata(for:inline:)` with a nil `inline` reaches the proxy for
        // any status, so a terminal row exercises the caching branch here even
        // though `PlaycutMetadataResolver` would have short-circuited it.
        _ = await service.fetchMetadata(for: playcut, inline: nil)

        let albumKey = MetadataCacheKey.album(
            artistName: "Csillagrablók",
            releaseTitle: "Nem Latszik Semmi"
        )
        let metadata = mockCache.metadata(for: albumKey)
        #expect(metadata != nil, "Album entry should be cached")
        #expect(
            metadata?.lifespan == .sevenDays,
            "Only a mid-enrichment row should get the short TTL"
        )
    }

    @Test("An enriched album response keeps the seven-day TTL")
    func enrichedAlbumKeepsSevenDayTTL() async throws {
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = MetadataV2MockWebSession()
        let service = PlaycutMetadataService(urlSession: mockSession.urlSession, cache: cache)

        // Mid-enrichment, so the enrichment-window gate is satisfied and the
        // seven days can only come from the payload carrying real enrichment.
        let playcut = Playcut.stub(
            songTitle: "Back, Baby",
            labelName: "Drag City",
            artistName: "Jessica Pratt",
            releaseTitle: "On Your Own Love Again",
            metadataStatus: .enriching
        )

        let albumResponse = """
        {
            "discogsReleaseId": null,
            "discogsUrl": "https://www.discogs.com/release/6577044",
            "releaseYear": 2015,
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

        // Then
        let albumKey = MetadataCacheKey.album(
            artistName: "Jessica Pratt",
            releaseTitle: "On Your Own Love Again"
        )
        let metadata = mockCache.metadata(for: albumKey)
        #expect(metadata?.lifespan == .sevenDays, "An album carrying enrichment should retain the .sevenDays TTL")
    }

    // MARK: - Explicit metadataStatus branch gates the proxy fetch (#270)

    @Test(
        "Every terminal-vs-non-terminal MetadataStatus value gates fetchMetadata's proxy call exactly per MetadataStatus.isTerminal",
        arguments: MetadataStatus.allCases
    )
    func fetchMetadataStatusGatesProxyCall(status: MetadataStatus) async throws {
        try await assertMetadataStatusGatesProxyCall(status: status, expectsProxyCall: !status.isTerminal)
    }

    @Test("fetchMetadata falls back to the proxy when metadataStatus is nil — V1 rows and decoder-absent feeds (#270)")
    func fetchMetadataNilStatusFallsBackToProxy() async throws {
        try await assertMetadataStatusGatesProxyCall(status: nil, expectsProxyCall: true)
    }

    /// Shared body for the `#270` status-gating tests above: holds inline
    /// streaming empty across every case so `metadataStatus` alone drives
    /// whether `fetchMetadata` reaches `/proxy/metadata/album` — a populated
    /// inline streaming URL would short-circuit independent of status (see
    /// "Inline V2 with at least one streaming URL skips the proxy fetch"
    /// above), which would confound a status-only assertion. This mirrors
    /// the decision `PlaycutMetadataResolver.resolve(for:)`'s explicit
    /// `metadataStatus` switch makes structurally (it never calls
    /// `fetchMetadata` at all for the three terminal statuses). This asserts
    /// the `PlaycutMetadataService` boundary; the resolver's own branch is
    /// covered directly in `PlaycutMetadataResolverTests`.
    private func assertMetadataStatusGatesProxyCall(status: MetadataStatus?, expectsProxyCall: Bool) async throws {
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = MetadataV2MockWebSession()
        let service = PlaycutMetadataService(urlSession: mockSession.urlSession, cache: cache)

        let playcut = Playcut.stub(
            songTitle: "la paradoja",
            labelName: "Sonamos",
            artistName: "Juana Molina",
            releaseTitle: "DOGA",
            metadataStatus: status
        )
        let inline = PlaycutMetadata(
            artist: ArtistMetadata(bio: "Argentine singer-songwriter."),
            album: AlbumMetadata(label: "Sonamos"),
            streaming: .empty
        )

        let albumResponse = """
        {
            "discogsReleaseId": null,
            "discogsUrl": null,
            "releaseYear": null,
            "spotifyUrl": "https://open.spotify.com/search/Juana%20Molina",
            "appleMusicUrl": null,
            "youtubeMusicUrl": null,
            "bandcampUrl": null,
            "soundcloudUrl": null
        }
        """.data(using: .utf8)!
        mockSession.responses["proxy/metadata/album"] = albumResponse

        let result = await service.fetchMetadata(for: playcut, inline: inline)

        if expectsProxyCall {
            #expect(mockSession.requestCount >= 1, "status \(String(describing: status)) must fall back to the proxy")
        } else {
            #expect(mockSession.requestCount == 0, "status \(String(describing: status)) must short-circuit to inline, no proxy call")
            #expect(result == inline)
        }
    }

    @Test("Populated streaming response keeps the seven-day TTL")
    func populatedStreamingKeepsSevenDayTTL() async throws {
        // Given
        let mockCache = PlaycutMetadataMockCache()
        let cache = CacheCoordinator(cache: mockCache)
        let mockSession = MetadataV2MockWebSession()
        let service = PlaycutMetadataService(urlSession: mockSession.urlSession, cache: cache)

        let playcut = Playcut.stub(
            songTitle: "Aluminum Tunes",
            labelName: "Duophonic",
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
