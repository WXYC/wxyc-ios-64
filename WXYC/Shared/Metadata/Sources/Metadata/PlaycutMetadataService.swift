//
//  PlaycutMetadataService.swift
//  Core
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

/// Service for fetching extended metadata about a playcut from various sources
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
        self.cache = .AlbumArt
    }
    
    // Internal initializer for testing
    init(session: WebSession, cache: CacheCoordinator = .AlbumArt) {
        self.session = session
        self.decoder = JSONDecoder()
        self.cache = cache
    }
    
    /// Cache lifespan: 7 days (metadata rarely changes)
    private static let cacheLifespan: TimeInterval = 60 * 60 * 24 * 7
    
    /// Fetches all available metadata for a playcut
    public func fetchMetadata(for playcut: Playcut) async -> PlaycutMetadata {
        let cacheKey = "playcut-metadata-\(playcut.id)"
        
        // Check cache first
        if let cached: PlaycutMetadata = try? await cache.value(for: cacheKey) {
            return cached
        }
        
        // Fetch from all sources concurrently
        async let discogsMetadata = fetchDiscogsMetadata(for: playcut)
        async let spotifyURL = fetchSpotifyURL(for: playcut)
        async let appleMusicURL = fetchAppleMusicURL(for: playcut)
        async let youtubeMusicURL = makeYouTubeMusicSearchURL(for: playcut)
        async let bandcampURL = makeBandcampSearchURL(for: playcut)
        async let soundcloudURL = makeSoundCloudSearchURL(for: playcut)
        
        let discogs = await discogsMetadata
        
        let metadata = PlaycutMetadata(
            label: discogs.label ?? playcut.labelName,
            releaseYear: discogs.releaseYear,
            discogsURL: discogs.discogsURL,
            artistBio: discogs.artistBio,
            wikipediaURL: discogs.wikipediaURL,
            spotifyURL: await spotifyURL,
            appleMusicURL: await appleMusicURL,
            youtubeMusicURL: await youtubeMusicURL,
            bandcampURL: await bandcampURL,
            soundcloudURL: await soundcloudURL
        )
        
        // Cache result
        await cache.set(value: metadata, for: cacheKey, lifespan: Self.cacheLifespan)
        
        return metadata
    }
}

// MARK: - Discogs Integration

extension PlaycutMetadataService {
    private struct DiscogsMetadata {
        let label: String?
        let releaseYear: Int?
        let discogsURL: URL?
        let artistBio: String?
        let wikipediaURL: URL?
    }
    
    private func fetchDiscogsMetadata(for playcut: Playcut) async -> DiscogsMetadata {
        do {
            // First, search for the release
            let searchResult = try await searchDiscogs(for: playcut)
            
            guard let result = searchResult else {
                return DiscogsMetadata(label: nil, releaseYear: nil, discogsURL: nil, artistBio: nil, wikipediaURL: nil)
            }
            
            // Try to fetch artist info for bio and Wikipedia link
            var artistBio: String?
            var wikipediaURL: URL?
            
            if result.type == "release",
               let resourceUrl = result.resourceUrl,
               let url = URL(string: resourceUrl) {
                // Fetch release details to get artist ID
                if let release = try? await fetchRelease(url: url),
                   let artistId = release.primaryArtistId {
                    let artistInfo = try? await fetchArtist(id: artistId)
                    artistBio = artistInfo?.profile
                    wikipediaURL = artistInfo?.wikipediaURL
                }
            } else if result.type == "master",
                      let resourceUrl = result.resourceUrl,
                      let url = URL(string: resourceUrl) {
                // Fetch master details to get artist ID
                if let master = try? await fetchMaster(url: url),
                   let artistId = master.primaryArtistId {
                    let artistInfo = try? await fetchArtist(id: artistId)
                    artistBio = artistInfo?.profile
                    wikipediaURL = artistInfo?.wikipediaURL
                }
            } else if result.type == "artist" {
                // Direct artist result
                let artistInfo = try? await fetchArtist(id: result.id)
                artistBio = artistInfo?.profile
                wikipediaURL = artistInfo?.wikipediaURL
            }
            
            return DiscogsMetadata(
                label: result.primaryLabel,
                releaseYear: result.releaseYear,
                discogsURL: result.discogsWebURL,
                artistBio: artistBio,
                wikipediaURL: wikipediaURL
            )
        } catch {
            Log(.error, "Failed to fetch Discogs metadata: \(error)")
            return DiscogsMetadata(label: nil, releaseYear: nil, discogsURL: nil, artistBio: nil, wikipediaURL: nil)
        }
    }
    
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
        case notFound
    }
}

