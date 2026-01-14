//
//  PlaycutMetadataService.swift
//  Metadata
//
//  Service for fetching and caching extended playcut metadata.
//
//  Created by Jake Bromberg on 11/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
import Artwork
import Secrets
import Logger
import Core
import Caching
import Playlist

// MARK: - PlaycutMetadataService

/// Service for fetching extended metadata about a playcut from various sources.
///
/// Uses multi-level caching to reduce redundant API calls:
/// - Artist metadata is cached by Discogs artist ID (30-day TTL)
/// - Album metadata is cached by artist+release key (7-day TTL)
/// - Streaming links are cached by artist+song key (7-day TTL)
public actor PlaycutMetadataService {
    private let session: WebSession
    private let decoder: JSONDecoder
    private let cache: CacheCoordinator

    // Discogs API credentials
    private static let discogsKey = Secrets.discogsApiKeyV2_5
    private static let discogsSecret = Secrets.discogsApiSecretV2_5

    // Spotify credentials
    private static let spotifyClientId = Secrets.spotifyClientId
    private static let spotifyClientSecret = Secrets.spotifyClientSecret

    // Cached Spotify token
    private var spotifyToken: String?
    private var spotifyTokenExpiration: Date?

    public init() {
        self.session = URLSession.shared
        self.decoder = JSONDecoder()
        self.cache = .Metadata
    }

    // Internal initializer for testing
    init(session: WebSession, cache: CacheCoordinator = .Metadata) {
        self.session = session
        self.decoder = JSONDecoder()
        self.cache = cache
    }

    /// Fetches all available metadata for a playcut using granular caching.
    ///
    /// This method caches at three levels:
    /// - Album metadata by artist+release (7-day TTL)
    /// - Artist metadata by Discogs artist ID (30-day TTL)
    /// - Streaming links by artist+song (7-day TTL)
    public func fetchMetadata(for playcut: Playcut) async -> PlaycutMetadata {
        // Fetch metadata at each granularity level concurrently
        async let albumResult = fetchAlbumMetadata(for: playcut)
        async let streamingResult = fetchStreamingLinks(for: playcut)

        let album = await albumResult

        // Artist metadata requires the Discogs artist ID from the album lookup
        let artist = await fetchArtistMetadata(discogsArtistId: album.discogsArtistId)

        return PlaycutMetadata(
            artist: artist,
            album: album,
            streaming: await streamingResult
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
            Log(.info, "Artist metadata cache hit for ID \(artistId)")
            return cached
        }

        // Fetch from Discogs
        do {
            let artist = try await fetchArtist(id: artistId)
            let metadata = ArtistMetadata(
                bio: artist.profile,
                wikipediaURL: artist.wikipediaURL,
                discogsArtistId: artistId
            )
    
            await cache.set(value: metadata, for: cacheKey, lifespan: .thirtyDays)
            return metadata
        } catch {
            Log(.error, "Failed to fetch artist metadata for ID \(artistId): \(error)")
            return .empty
        }
    }

    /// Fetches album metadata, caching by artist+release key.
    private func fetchAlbumMetadata(for playcut: Playcut) async -> AlbumMetadata {
        let cacheKey = MetadataCacheKey.album(
            artistName: playcut.artistName,
            releaseTitle: playcut.releaseTitle ?? ""
        )

        // Check cache
        if let cached: AlbumMetadata = try? await cache.value(for: cacheKey) {
            Log(.info, "Album metadata cache hit for \(playcut.artistName) - \(playcut.releaseTitle ?? "nil")")
            return cached
        }

        // Fetch from Discogs
        Log(.info, "Fetching album metadata for: \(playcut.artistName) - \(playcut.releaseTitle ?? "nil")")

        do {
            let searchResult = try await searchDiscogs(for: playcut)

            guard let result = searchResult else {
                Log(.warning, "No Discogs search results found for: \(playcut.artistName)")
                let metadata = AlbumMetadata(label: playcut.labelName)
                await cache.set(value: metadata, for: cacheKey, lifespan: .sevenDays)
                return metadata
            }

            Log(.info, "Found Discogs result: type=\(result.type), id=\(result.id)")

            // Extract artist ID from release/master details
            let artistId = await extractArtistId(from: result)

            let metadata = AlbumMetadata(
                label: result.primaryLabel ?? playcut.labelName,
                releaseYear: result.releaseYear,
                discogsURL: result.discogsWebURL,
                discogsArtistId: artistId
            )

            await cache.set(value: metadata, for: cacheKey, lifespan: .sevenDays)
            return metadata
        } catch {
            Log(.error, "Failed to fetch album metadata: \(error)")
            let metadata = AlbumMetadata(label: playcut.labelName)
            await cache.set(value: metadata, for: cacheKey, lifespan: .sevenDays)
            return metadata
        }
    }

    /// Fetches streaming links, caching by artist+song key.
    private func fetchStreamingLinks(for playcut: Playcut) async -> StreamingLinks {
        let cacheKey = MetadataCacheKey.streaming(
            artistName: playcut.artistName,
            songTitle: playcut.songTitle
        )
        
        // Check cache
        if let cached: StreamingLinks = try? await cache.value(for: cacheKey) {
            Log(.info, "Streaming links cache hit for \(playcut.artistName) - \(playcut.songTitle)")
            return cached
        }

        // Fetch from all streaming services concurrently
        async let spotifyURL = fetchSpotifyURL(for: playcut)
        async let appleMusicURL = fetchAppleMusicURL(for: playcut)
        async let youtubeMusicURL = makeYouTubeMusicSearchURL(for: playcut)
        async let bandcampURL = makeBandcampSearchURL(for: playcut)
        async let soundcloudURL = makeSoundCloudSearchURL(for: playcut)
        
        let links = StreamingLinks(
            spotifyURL: await spotifyURL,
            appleMusicURL: await appleMusicURL,
            youtubeMusicURL: await youtubeMusicURL,
            bandcampURL: await bandcampURL,
            soundcloudURL: await soundcloudURL
        )

        await cache.set(value: links, for: cacheKey, lifespan: .sevenDays)
        return links
    }

    /// Extracts the primary artist ID from a Discogs search result.
    private func extractArtistId(from result: Discogs.SearchResult) async -> Int? {
        if result.type == "artist" {
            return result.id
        }

        if result.type == "release",
           let resourceUrl = result.resourceUrl,
           let url = URL(string: resourceUrl) {
            if let release = try? await fetchRelease(url: url) {
                return release.primaryArtistId
            }
        }

        if result.type == "master",
           let resourceUrl = result.resourceUrl,
           let url = URL(string: resourceUrl) {
            if let master = try? await fetchMaster(url: url) {
                return master.primaryArtistId
            }
        }

        return nil
    }
}

// MARK: - Discogs Integration

extension PlaycutMetadataService {
    private func searchDiscogs(for playcut: Playcut) async throws -> Discogs.SearchResult? {
        var releaseTitle = playcut.releaseTitle
        if let title = playcut.releaseTitle, title.lowercased() == "s/t" {
            releaseTitle = playcut.artistName
        }
        
        var searchTerms = [playcut.artistName]
        if let releaseTitle {
            searchTerms.append(releaseTitle)
        }
        
        var components = URLComponents(string: "https://api.discogs.com")!
        components.path = "/database/search"
        components.queryItems = [
            URLQueryItem(name: "q", value: searchTerms.joined(separator: " ")),
            URLQueryItem(name: "key", value: Self.discogsKey),
            URLQueryItem(name: "secret", value: Self.discogsSecret)
        ]
        
        let data = try await session.data(from: components.url!)
        let response = try decoder.decode(Discogs.SearchResults.self, from: data)
        
        // Find a valid result (skip spacer.gif placeholders)
        return response.results.first { result in
            !result.coverImage.lastPathComponent.hasPrefix("spacer.gif")
        }
    }
            
    private func fetchRelease(url: URL) async throws -> Discogs.Release {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "key", value: Self.discogsKey),
            URLQueryItem(name: "secret", value: Self.discogsSecret)
        ]
        
        let data = try await session.data(from: components.url!)
        return try decoder.decode(Discogs.Release.self, from: data)
    }
    
    private func fetchMaster(url: URL) async throws -> Discogs.Master {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "key", value: Self.discogsKey),
            URLQueryItem(name: "secret", value: Self.discogsSecret)
        ]
        
        let data = try await session.data(from: components.url!)
        return try decoder.decode(Discogs.Master.self, from: data)
    }
    
    private func fetchArtist(id: Int) async throws -> Discogs.Artist {
        var components = URLComponents(string: "https://api.discogs.com")!
        components.path = "/artists/\(id)"
        components.queryItems = [
            URLQueryItem(name: "key", value: Self.discogsKey),
            URLQueryItem(name: "secret", value: Self.discogsSecret)
        ]
        
        let data = try await session.data(from: components.url!)
        return try decoder.decode(Discogs.Artist.self, from: data)
    }
}

// MARK: - Spotify Integration

extension PlaycutMetadataService {
    private func fetchSpotifyURL(for playcut: Playcut) async -> URL? {
        do {
            let token = try await getSpotifyToken()
            
            var query = "track:\(playcut.songTitle) artist:\(playcut.artistName)"
            if let album = playcut.releaseTitle {
                query += " album:\(album)"
            }
            
            var components = URLComponents(string: "https://api.spotify.com")!
            components.path = "/v1/search"
            components.queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "type", value: "track"),
                URLQueryItem(name: "limit", value: "1")
            ]
            
            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, _) = try await URLSession.shared.data(for: request)

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tracks = json["tracks"] as? [String: Any],
                  let items = tracks["items"] as? [[String: Any]],
                  let firstTrack = items.first,
                  let externalUrls = firstTrack["external_urls"] as? [String: String],
                  let spotifyUrlString = externalUrls["spotify"],
                  let spotifyUrl = URL(string: spotifyUrlString) else {
                return nil
            }
            
            return spotifyUrl
        } catch {
            Log(.error, "Failed to fetch Spotify URL: \(error)")
            return nil
        }
    }
    
    private func getSpotifyToken() async throws -> String {
        // Return cached token if valid
        if let token = spotifyToken,
           let expiration = spotifyTokenExpiration,
           Date() < expiration.addingTimeInterval(-60) {
            return token
        }
        
        // Fetch new token using Client Credentials flow
        let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!
        
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let credentialString = "\(Self.spotifyClientId):\(Self.spotifyClientSecret)"
        let base64Credentials = Data(credentialString.utf8).base64EncodedString()
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        
        request.httpBody = "grant_type=client_credentials".data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MetadataError.authenticationFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let expiresIn = json["expires_in"] as? Int else {
            throw MetadataError.invalidResponse
        }
        
        spotifyToken = accessToken
        spotifyTokenExpiration = Date().addingTimeInterval(TimeInterval(expiresIn))
        
        return accessToken
    }
}

// MARK: - Apple Music / iTunes Integration

extension PlaycutMetadataService {
    private func fetchAppleMusicURL(for playcut: Playcut) async -> URL? {
        do {
            let query = "\(playcut.artistName) \(playcut.songTitle)"
            
            var components = URLComponents(string: "https://itunes.apple.com")!
            components.path = "/search"
            components.queryItems = [
                URLQueryItem(name: "term", value: query),
                URLQueryItem(name: "entity", value: "song"),
                URLQueryItem(name: "media", value: "music"),
                URLQueryItem(name: "limit", value: "1")
            ]
            
            let data = try await session.data(from: components.url!)
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let firstResult = results.first,
                  let trackViewUrlString = firstResult["trackViewUrl"] as? String,
                  let trackViewUrl = URL(string: trackViewUrlString) else {
                return nil
            }

            return trackViewUrl
        } catch {
            Log(.error, "Failed to fetch Apple Music URL: \(error)")
            return nil
        }
    }
}

// MARK: - YouTube Music

extension PlaycutMetadataService {
    /// Creates a YouTube Music search URL for the playcut
    /// Note: YouTube Data API requires an API key, so we construct a search URL instead
    private func makeYouTubeMusicSearchURL(for playcut: Playcut) async -> URL? {
        let query = "\(playcut.artistName) \(playcut.songTitle)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        return URL(string: "https://music.youtube.com/search?q=\(query)")
    }
}

// MARK: - Bandcamp

extension PlaycutMetadataService {
    /// Creates a Bandcamp search URL for the playcut
    /// Note: Bandcamp doesn't have a public API for search
    private func makeBandcampSearchURL(for playcut: Playcut) async -> URL? {
        let query = "\(playcut.artistName) \(playcut.songTitle)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        return URL(string: "https://bandcamp.com/search?q=\(query)")
    }
}

// MARK: - SoundCloud

extension PlaycutMetadataService {
    /// Creates a SoundCloud search URL for the playcut
    /// Note: SoundCloud API is restricted, so we construct a search URL instead
    private func makeSoundCloudSearchURL(for playcut: Playcut) async -> URL? {
        let query = "\(playcut.artistName) \(playcut.songTitle)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        return URL(string: "https://soundcloud.com/search?q=\(query)")
    }
}

// MARK: - Errors

extension PlaycutMetadataService {
    enum MetadataError: Error {
        case authenticationFailed
        case invalidResponse
    }
}
