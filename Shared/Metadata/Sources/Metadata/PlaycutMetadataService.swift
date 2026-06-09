//
//  PlaycutMetadataService.swift
//  Metadata
//
//  Service for fetching and caching extended playcut metadata via backend proxy.
//
//  Created by Jake Bromberg on 11/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
import Artwork
import Logger
import Core
import Caching
import Playlist

// MARK: - PlaycutMetadataService

/// Service for fetching extended metadata about a playcut from the backend proxy.
///
/// Uses multi-level caching to reduce redundant API calls:
/// - Artist metadata is cached by Discogs artist ID (30-day TTL)
/// - Album metadata is cached by artist+release key (7-day TTL)
/// - Streaming links are cached by artist+song key (7-day TTL when populated,
///   ``emptyStreamingLifespan`` when every streaming URL came back nil)
public actor PlaycutMetadataService {
    /// Short TTL applied to streaming-cache entries that came back with every
    /// URL nil. Long enough to absorb back-to-back views of the same playcut
    /// within an iOS session without re-hitting the proxy, short enough that a
    /// freshly-enriched row (BS read-path or LML reconciliation landing the
    /// streaming URL minutes later) supersedes the empty entry rather than
    /// being shadowed for a week.
    static let emptyStreamingLifespan: TimeInterval = 15 * 60

    private let baseURL: URL
    private let tokenProvider: SessionTokenProvider?
    private let session: WebSession
    private let urlSession: URLSession
    private let cache: CacheCoordinator
    private let errorReporter: any ErrorReporter

    public init(
        baseURL: URL = URL(string: "https://api.wxyc.org")!,
        tokenProvider: SessionTokenProvider? = nil,
        errorReporter: any ErrorReporter = ErrorReporting.shared
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.session = URLSession.shared
        self.urlSession = .shared
        self.cache = .Metadata
        self.errorReporter = errorReporter
    }

    // Internal initializer for testing
    init(
        baseURL: URL = URL(string: "https://api.wxyc.org")!,
        tokenProvider: SessionTokenProvider? = nil,
        session: WebSession,
        urlSession: URLSession = .shared,
        cache: CacheCoordinator = .Metadata,
        errorReporter: any ErrorReporter = ErrorReporting.shared
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.session = session
        self.urlSession = urlSession
        self.cache = cache
        self.errorReporter = errorReporter
    }

    /// Fetches all available metadata for a playcut using granular caching.
    ///
    /// This method caches at three levels:
    /// - Album metadata by artist+release (7-day TTL)
    /// - Artist metadata by Discogs artist ID (30-day TTL)
    /// - Streaming links by artist+song (7-day TTL when populated,
    ///   ``emptyStreamingLifespan`` when every URL came back nil)
    public func fetchMetadata(for playcut: Playcut) async -> PlaycutMetadata {
        await fetchMetadata(for: playcut, inline: nil)
    }

    /// Fetches metadata, optionally seeded by an inline V2 flowsheet row.
    ///
    /// When `inline` is non-nil and already carries at least one streaming URL,
    /// the inline metadata is returned directly with no network call. When the
    /// inline row exists but every streaming URL is nil (Tragic Magic shape —
    /// the V2 writer landed the artwork/Discogs columns but no streaming side),
    /// the service falls through to `/proxy/metadata/album` so the BS read path
    /// can fill the streaming gap. Inline album- and artist-level fields are
    /// preserved when the proxy omits them.
    ///
    /// - Parameters:
    ///   - playcut: The playcut to resolve metadata for.
    ///   - inline: Optional inline metadata constructed from the V2 flowsheet
    ///     response. Pass `nil` to behave like the V1 path.
    public func fetchMetadata(for playcut: Playcut, inline: PlaycutMetadata?) async -> PlaycutMetadata {
        if let inline, inline.streaming.hasAny {
            return inline
        }

        // Either no inline metadata at all, or inline-but-empty-streaming.
        // In both cases we want the proxy fetch so the BS read path can
        // contribute streaming URLs that the inline V2 write path missed.
        let (album, streaming) = await fetchAlbumAndStreaming(for: playcut)

        // Artist metadata requires the Discogs artist ID from the album lookup
        let artist = await fetchArtistMetadata(discogsArtistId: album.discogsArtistId)

        guard let inline else {
            return PlaycutMetadata(artist: artist, album: album, streaming: streaming)
        }

        // Inline fallthrough: prefer the proxy result where present, else fall
        // back to the inline values. This protects inline album fields (label,
        // releaseYear) and the inline artist bio when the proxy returns only
        // streaming URLs.
        return PlaycutMetadata(
            artist: artist == .empty ? inline.artist : artist,
            album: Self.mergeAlbum(proxy: album, inline: inline.album),
            streaming: streaming
        )
    }

    /// Coalesces two `AlbumMetadata` records field-by-field, preferring `proxy`
    /// values where present and falling back to `inline` otherwise. Used on the
    /// V2 fallthrough path so inline album fields the proxy didn't refresh
    /// (label, releaseYear, artworkURL on the LML synth-shape) survive.
    private static func mergeAlbum(proxy: AlbumMetadata, inline: AlbumMetadata) -> AlbumMetadata {
        AlbumMetadata(
            label: proxy.label ?? inline.label,
            releaseYear: proxy.releaseYear ?? inline.releaseYear,
            discogsURL: proxy.discogsURL ?? inline.discogsURL,
            discogsArtistId: proxy.discogsArtistId ?? inline.discogsArtistId,
            genres: proxy.genres ?? inline.genres,
            styles: proxy.styles ?? inline.styles,
            fullReleaseDate: proxy.fullReleaseDate ?? inline.fullReleaseDate,
            artworkURL: proxy.artworkURL ?? inline.artworkURL
        )
    }

    // MARK: - Granular Caching Methods

    /// Fetches artist metadata, caching by Discogs artist ID.
    private func fetchArtistMetadata(discogsArtistId: Int?) async -> ArtistMetadata {
        guard let artistId = discogsArtistId else {
            return .empty
        }

        let cacheKey = MetadataCacheKey.artist(discogsId: artistId)

        return (try? await cachedFetch(
            key: cacheKey,
            cache: cache,
            lifespan: .thirtyDays,
            fetch: {
                let response = try await fetchFromProxy(
                    path: "proxy/metadata/artist",
                    queryItems: [URLQueryItem(name: "artistId", value: String(artistId))]
                )
                return try JSONDecoder.shared.decode(ArtistMetadataAPIResponse.self, from: response)
            },
            transform: { apiResult in
                ArtistMetadata(
                    bio: apiResult.bio,
                    bioTokens: apiResult.bioTokens,
                    wikipediaURL: apiResult.wikipediaUrl.flatMap { URL(string: $0) },
                    discogsArtistId: apiResult.discogsArtistId ?? artistId,
                    imageURL: apiResult.artistImageUrl.flatMap { URL(string: $0) }
                )
            }
        )) ?? .empty
    }

    /// Fetches album metadata and streaming links from the backend proxy in a single call.
    ///
    /// Deliberately not refactored onto `cachedFetch`: one network response feeds two
    /// caches with different keys (`.album(artist, release)` and `.streaming(artist, song)`),
    /// and a partial cache hit on either side must still issue the fetch but only write the
    /// missing side. The existing single-key `cachedFetch` overloads can't model that without
    /// a bespoke 2-cache variant, and this is the only caller that would need it. See #192.
    private func fetchAlbumAndStreaming(for playcut: Playcut) async -> (AlbumMetadata, StreamingLinks) {
        let albumCacheKey = MetadataCacheKey.album(
            artistName: playcut.artistName,
            releaseTitle: playcut.releaseTitle ?? ""
        )
        let streamingCacheKey = MetadataCacheKey.streaming(
            artistName: playcut.artistName,
            songTitle: playcut.songTitle
        )

        // Check both caches
        let cachedAlbum: AlbumMetadata? = try? await cache.value(for: albumCacheKey)
        let cachedStreaming: StreamingLinks? = try? await cache.value(for: streamingCacheKey)

        if let album = cachedAlbum, let streaming = cachedStreaming {
            Log(.info, category: .network, "Album+streaming cache hit for \(playcut.artistName)")
            return (album, streaming)
        }

        let fallbackAlbum = cachedAlbum ?? AlbumMetadata(label: playcut.labelName)
        let fallbackStreaming = cachedStreaming ?? .empty

        return await timedOperation(
            context: "fetchAlbumAndStreaming(\(playcut.artistName))",
            category: .network,
            fallback: (fallbackAlbum, fallbackStreaming),
            errorReporter: errorReporter
        ) {
            var queryItems = [URLQueryItem(name: "artistName", value: playcut.artistName)]
            if let releaseTitle = playcut.releaseTitle {
                let title = releaseTitle.lowercased() == "s/t" ? playcut.artistName : releaseTitle
                queryItems.append(URLQueryItem(name: "releaseTitle", value: title))
            }
            queryItems.append(URLQueryItem(name: "trackTitle", value: playcut.songTitle))

            let data = try await fetchFromProxy(path: "proxy/metadata/album", queryItems: queryItems)
            let apiResult = try JSONDecoder.shared.decode(AlbumMetadataAPIResponse.self, from: data)

            let album = cachedAlbum ?? AlbumMetadata(
                label: apiResult.label ?? playcut.labelName,
                releaseYear: apiResult.releaseYear,
                discogsURL: apiResult.discogsUrl.flatMap { URL(string: $0) },
                discogsArtistId: apiResult.discogsArtistId,
                genres: apiResult.genres,
                styles: apiResult.styles,
                fullReleaseDate: apiResult.fullReleaseDate,
                artworkURL: apiResult.artworkUrl.flatMap { URL(string: $0) }
            )

            let streaming = cachedStreaming ?? StreamingLinks(
                spotifyURL: apiResult.spotifyUrl.flatMap { URL(string: $0) },
                appleMusicURL: apiResult.appleMusicUrl.flatMap { URL(string: $0) },
                youtubeMusicURL: apiResult.youtubeMusicUrl.flatMap { URL(string: $0) },
                bandcampURL: apiResult.bandcampUrl.flatMap { URL(string: $0) },
                soundcloudURL: apiResult.soundcloudUrl.flatMap { URL(string: $0) }
            )

            if cachedAlbum == nil {
                await cache.set(value: album, for: albumCacheKey, lifespan: .sevenDays)
            }
            if cachedStreaming == nil {
                // Short-TTL on empty-streaming entries so a freshly-enriched row
                // supersedes within the same iOS session rather than being shadowed
                // for a week (#303).
                let streamingLifespan: TimeInterval = streaming.hasAny ? .sevenDays : Self.emptyStreamingLifespan
                await cache.set(value: streaming, for: streamingCacheKey, lifespan: streamingLifespan)
            }

            return (album, streaming)
        }
    }

    // MARK: - Network

    private func fetchFromProxy(path: String, queryItems: [URLQueryItem]) async throws -> Data {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems

        guard let url = components.url else {
            throw MetadataError.invalidURL
        }

        if let tokenProvider {
            let token = try await tokenProvider.token()
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await urlSession.data(for: request)
            try (response as? HTTPURLResponse)?.validateSuccessStatus()
            return data
        } else {
            return try await session.data(from: url)
        }
    }
}

// MARK: - Backend API Response Models

private struct AlbumMetadataAPIResponse: Codable {
    let discogsReleaseId: Int?
    let discogsArtistId: Int?
    let discogsUrl: String?
    let releaseYear: Int?
    let artworkUrl: String?
    let genres: [String]?
    let styles: [String]?
    let label: String?
    let fullReleaseDate: String?
    let spotifyUrl: String?
    let appleMusicUrl: String?
    let youtubeMusicUrl: String?
    let bandcampUrl: String?
    let soundcloudUrl: String?
}

private struct ArtistMetadataAPIResponse: Codable {
    let discogsArtistId: Int?
    let bio: String?
    let bioTokens: [ResolvedBioToken]?
    let wikipediaUrl: String?
    let artistImageUrl: String?
}

// MARK: - Errors

extension PlaycutMetadataService {
    enum MetadataError: Error {
        case invalidURL
        case httpError(statusCode: Int)
    }
}
