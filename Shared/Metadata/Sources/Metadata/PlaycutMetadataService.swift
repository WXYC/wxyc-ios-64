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
/// - Streaming links are cached by artist+song key (7-day TTL)
public actor PlaycutMetadataService {
    private let baseURL: URL
    private let tokenProvider: SessionTokenProvider?
    private let session: WebSession
    private let urlSession: URLSession
    private let decoder: JSONDecoder
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
        self.decoder = JSONDecoder()
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
        self.decoder = JSONDecoder()
        self.cache = cache
        self.errorReporter = errorReporter
    }

    /// Fetches all available metadata for a playcut using granular caching.
    ///
    /// This method caches at three levels:
    /// - Album metadata by artist+release (7-day TTL)
    /// - Artist metadata by Discogs artist ID (30-day TTL)
    /// - Streaming links by artist+song (7-day TTL)
    public func fetchMetadata(for playcut: Playcut) async -> PlaycutMetadata {
        // Fetch album metadata (includes streaming links from backend)
        let (album, streaming) = await fetchAlbumAndStreaming(for: playcut)

        // Artist metadata requires the Discogs artist ID from the album lookup
        let artist = await fetchArtistMetadata(discogsArtistId: album.discogsArtistId)

        return PlaycutMetadata(
            artist: artist,
            album: album,
            streaming: streaming
        )
    }

    // MARK: - Granular Caching Methods

    /// Fetches artist metadata, caching by Discogs artist ID.
    private func fetchArtistMetadata(discogsArtistId: Int?) async -> ArtistMetadata {
        guard let artistId = discogsArtistId else {
            return .empty
        }

        let cacheKey = MetadataCacheKey.artist(discogsId: artistId)

        // Check cache
        if let cached: ArtistMetadata = try? await cache.value(for: cacheKey) {
            Log(.info, category: .network, "Artist metadata cache hit for ID \(artistId)")
            return cached
        }

        return await timedOperation(
            context: "fetchArtistMetadata(ID: \(artistId))",
            category: .network,
            fallback: .empty,
            errorReporter: errorReporter
        ) {
            let response = try await fetchFromProxy(
                path: "proxy/metadata/artist",
                queryItems: [URLQueryItem(name: "artistId", value: String(artistId))]
            )

            let apiResult = try decoder.decode(ArtistMetadataAPIResponse.self, from: response)
            let metadata = ArtistMetadata(
                bio: apiResult.bio,
                wikipediaURL: apiResult.wikipediaUrl.flatMap { URL(string: $0) },
                discogsArtistId: apiResult.discogsArtistId ?? artistId
            )

            await cache.set(value: metadata, for: cacheKey, lifespan: .thirtyDays)
            return metadata
        }
    }

    /// Fetches album metadata and streaming links from the backend proxy in a single call.
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
            let apiResult = try decoder.decode(AlbumMetadataAPIResponse.self, from: data)

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
                await cache.set(value: streaming, for: streamingCacheKey, lifespan: .sevenDays)
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
    let wikipediaUrl: String?
}

// MARK: - Errors

extension PlaycutMetadataService {
    enum MetadataError: Error {
        case invalidURL
        case httpError(statusCode: Int)
    }
}
