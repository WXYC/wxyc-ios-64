//
//  SpotifyService.swift
//  MusicShareKit
//
//  Spotify URL parsing and track metadata extraction via backend proxy.
//
//  Created by Jake Bromberg on 11/24/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Core
import Foundation

enum SpotifyError: Error {
    case notConfigured
    case authenticationFailed
    case trackNotFound
    case invalidResponse
}

final class SpotifyService: MusicService {
    let identifier: MusicServiceIdentifier = .spotify

    init() {}

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
            let path = url.absoluteString.replacing("spotify:", with: "")
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
        track.artworkURL
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

        // Get auth token from AuthenticationService
        guard let authService = MusicShareKit.authService else {
            throw SpotifyError.notConfigured
        }

        let token = try await authService.ensureAuthenticated()
        let config = MusicShareKit.configuration

        // Call backend proxy instead of Spotify API directly
        guard let baseURL = config.authBaseURL.flatMap({ URL(string: $0) })?.deletingLastPathComponent() else {
            throw SpotifyError.notConfigured
        }

        let apiURL = baseURL.appending(path: "proxy/spotify/track/\(id)")
        var request = URLRequest(url: apiURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SpotifyError.trackNotFound
        }

        let json = try JSONDecoder.shared.decode(SpotifyTrackProxyResponse.self, from: data)

        return MusicTrack(
            service: track.service,
            url: track.url,
            title: json.title.isEmpty ? track.title : json.title,
            artist: json.artist.isEmpty ? track.artist : json.artist,
            album: json.album.isEmpty ? track.album : json.album,
            identifier: track.identifier,
            artworkURL: json.artworkUrl.flatMap { URL(string: $0) } ?? track.artworkURL
        )
    }
}

// MARK: - Backend Proxy Response

private struct SpotifyTrackProxyResponse: Codable {
    let title: String
    let artist: String
    let album: String
    let artworkUrl: String?
}
