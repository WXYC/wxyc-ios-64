//
//  SpotifyService.swift
//  MusicShareKit
//
//  Spotify URL parsing and track metadata extraction.
//
//  Created by Jake Bromberg on 11/24/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation

/// Configuration for Spotify API credentials
public struct SpotifyCredentials: Sendable {
    public let clientId: String
    public let clientSecret: String
    
    public init(clientId: String, clientSecret: String) {
        self.clientId = clientId
        self.clientSecret = clientSecret
    }
}

/// Manages Spotify OAuth token fetching and caching
actor SpotifyTokenManager {
    static let shared = SpotifyTokenManager()
    
    private var cachedToken: String?
    private var tokenExpiration: Date?
    private var credentials: SpotifyCredentials?
    
    private init() {}
    
    /// Configure the token manager with Spotify credentials
    func configure(with credentials: SpotifyCredentials) {
        self.credentials = credentials
        // Invalidate cached token when credentials change
        self.cachedToken = nil
        self.tokenExpiration = nil
    }
    
    func getAccessToken() async throws -> String {
        guard let credentials = credentials else {
            throw SpotifyError.notConfigured
        }
        
        // Return cached token if still valid (with 60 second buffer)
        if let token = cachedToken,
           let expiration = tokenExpiration,
           Date() < expiration.addingTimeInterval(-60) {
            return token
        }
        
        // Fetch new token using Client Credentials flow
        let token = try await fetchNewToken(credentials: credentials)
        return token
    }
    
    private func fetchNewToken(credentials: SpotifyCredentials) async throws -> String {
        let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!
        
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // Create Basic auth header from client credentials
        let credentialString = "\(credentials.clientId):\(credentials.clientSecret)"
        let credentialsData = credentialString.data(using: .utf8)!
        let base64Credentials = credentialsData.base64EncodedString()
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        
        // Request body
        request.httpBody = "grant_type=client_credentials".data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SpotifyError.authenticationFailed
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let accessToken = json?["access_token"] as? String,
              let expiresIn = json?["expires_in"] as? Int else {
            throw SpotifyError.invalidTokenResponse
        }
        
        // Cache the token
        cachedToken = accessToken
        tokenExpiration = Date().addingTimeInterval(TimeInterval(expiresIn))
        
        return accessToken
    }
}

enum SpotifyError: Error {
    case notConfigured
    case authenticationFailed
    case invalidTokenResponse
    case trackNotFound
    case invalidResponse
}

final class SpotifyService: MusicService {
    let identifier: MusicServiceIdentifier = .spotify
    
    init() {}
    
    /// Configure Spotify API credentials. Must be called before fetchMetadata.
    static func configure(credentials: SpotifyCredentials) async {
        await SpotifyTokenManager.shared.configure(with: credentials)
    }
    
    func canHandle(url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        let scheme = url.scheme?.lowercased() ?? ""
        
        return host.contains("open.spotify.com") || host.contains("spotify.com") || scheme == "spotify"
    }
    
    func parse(url: URL) -> MusicTrack? {
        guard canHandle(url: url) else { return nil }
        
        // Handle spotify: scheme URLs
        // Format: spotify:track:4iV5W9uYEdYUVa79Axb7Rh
        if url.scheme?.lowercased() == "spotify" {
            let path = url.absoluteString.replacingOccurrences(of: "spotify:", with: "")
            let components = path.split(separator: ":")
            
            if components.count >= 2 {
                let type = String(components[0])
                let id = String(components[1])
                
                return MusicTrack(
                    service: .spotify,
                    url: url,
                    title: nil,
                    artist: nil,
                    album: nil,
                    identifier: "\(type):\(id)"
                )
            }
        }
        
        // Handle https://open.spotify.com URLs
        // Format: https://open.spotify.com/track/4iV5W9uYEdYUVa79Axb7Rh
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        
        guard pathComponents.count >= 2 else { return nil }
        
        let type = pathComponents[0] // "track", "album", "artist", "playlist"
        let id = pathComponents[1]
        
        return MusicTrack(
            service: .spotify,
            url: url,
            title: nil,
            artist: nil,
            album: nil,
            identifier: "\(type):\(id)"
        )
    }
    
    func fetchArtwork(for track: MusicTrack) async throws -> URL? {
        // Artwork is fetched as part of fetchMetadata, return cached value
        return track.artworkURL
    }
    
    func fetchMetadata(for track: MusicTrack) async throws -> MusicTrack {
        guard let identifier = track.identifier else { return track }
        
        // Parse type and ID from identifier (format: "track:abc123")
        let components = identifier.split(separator: ":")
        guard components.count >= 2 else { return track }
        
        let type = String(components[0])
        let id = String(components[1])
        
        // Only fetch metadata for tracks
        guard type == "track" else { return track }
        
        // Get OAuth access token
        let accessToken = try await SpotifyTokenManager.shared.getAccessToken()
        
        // Fetch track data from Spotify Web API
        let apiURL = URL(string: "https://api.spotify.com/v1/tracks/\(id)")!
        
        var request = URLRequest(url: apiURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SpotifyError.trackNotFound
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SpotifyError.invalidResponse
        }
        
        // Extract metadata from response
        let title = json["name"] as? String
        
        // Get first artist name
        var artist: String?
        if let artists = json["artists"] as? [[String: Any]],
           let firstArtist = artists.first {
            artist = firstArtist["name"] as? String
        }
        
        // Get album name and artwork
        var album: String?
        var artworkURL: URL?
        if let albumObj = json["album"] as? [String: Any] {
            album = albumObj["name"] as? String
            
            // Get largest artwork image
            if let images = albumObj["images"] as? [[String: Any]],
               let firstImage = images.first,
               let urlString = firstImage["url"] as? String {
                artworkURL = URL(string: urlString)
            }
        }
        
        return MusicTrack(
            service: track.service,
            url: track.url,
            title: title ?? track.title,
            artist: artist ?? track.artist,
            album: album ?? track.album,
            identifier: track.identifier,
            artworkURL: artworkURL ?? track.artworkURL
        )
    }
}
