//
//  AppleMusicService.swift
//  MusicShareKit
//
//  Apple Music URL parsing and track metadata extraction.
//
//  Created by Jake Bromberg on 11/24/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation

final class AppleMusicService: MusicService {
    let identifier: MusicServiceIdentifier = .appleMusic
    
    init() {}
    
    func canHandle(url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        let scheme = url.scheme?.lowercased() ?? ""
        
        return host.contains("music.apple.com") || scheme == "music"
    }
    
    func parse(url: URL) -> MusicTrack? {
        guard canHandle(url: url) else { return nil }
        
        var identifier: String?
        
        // Handle music:// scheme URLs
        if url.scheme?.lowercased() == "music" {
            let pathComponents = url.pathComponents
            if pathComponents.count >= 3 {
                let type = pathComponents[1]
                let id = pathComponents[2]
                identifier = "\(type):\(id)"
            }
        } else {
            // Handle https://music.apple.com URLs
            // Format: https://music.apple.com/[country]/[type]/[name]/[id]?i=[trackId]
            
            // Extract track ID from query parameter if present (this is the song ID)
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let trackId = components.queryItems?.first(where: { $0.name == "i" })?.value {
                identifier = trackId
            } else {
                // Fall back to album ID from path
                let pathComponents = url.pathComponents.filter { $0 != "/" }
                if pathComponents.count >= 4 {
                    identifier = pathComponents[3]
                }
            }
        }
        
        guard identifier != nil else { return nil }
        
        return MusicTrack(
            service: .appleMusic,
            url: url,
            title: nil,
            artist: nil,
            album: nil,
            identifier: identifier
        )
    }
    
    func fetchArtwork(for track: MusicTrack) async throws -> URL? {
        // Artwork is fetched as part of fetchMetadata, return cached value
        return track.artworkURL
    }
    
    func fetchMetadata(for track: MusicTrack) async throws -> MusicTrack {
        guard let trackId = track.identifier else { return track }
        
        // Extract numeric ID from identifier (could be "album:123" or just "123")
        let numericId = trackId.components(separatedBy: ":").last ?? trackId
        
        // Use iTunes Lookup API to get full metadata (no auth required)
        let apiURL = URL(string: "https://itunes.apple.com/lookup?id=\(numericId)")!
        let (data, _) = try await URLSession.shared.data(from: apiURL)
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let firstResult = results.first else {
            return track
        }
        
        // Extract metadata from response
        // Use trackName for songs, fall back to collectionName for album shares
        let title = firstResult["trackName"] as? String ?? firstResult["collectionName"] as? String
        let artist = firstResult["artistName"] as? String
        let album = firstResult["collectionName"] as? String
        
        // Get artwork URL and upgrade to high resolution
        var artworkURL: URL?
        if let artworkUrlString = firstResult["artworkUrl100"] as? String {
            // Replace 100x100 with 600x600 for higher resolution
            let highResUrl = artworkUrlString.replacingOccurrences(of: "100x100", with: "600x600")
            artworkURL = URL(string: highResUrl)
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
