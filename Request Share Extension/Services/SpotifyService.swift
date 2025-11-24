//
//  SpotifyService.swift
//  Request Share Extension
//
//  Created by Jake Bromberg on 11/24/25.
//

import Foundation

class SpotifyService: MusicService {
    let identifier: MusicServiceIdentifier = .spotify
    
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
                let type = String(components[0]) // "track", "album", "artist"
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
        
        // Extract additional info from URL if available
        // Some URLs have format: https://open.spotify.com/track/4iV5W9uYEdYUVa79Axb7Rh?si=...
        var identifier = id
        if let query = url.query, !query.isEmpty {
            // Keep the base ID, query params are usually for sharing/analytics
        }
        
        return MusicTrack(
            service: .spotify,
            url: url,
            title: nil,
            artist: nil,
            album: nil,
            identifier: "\(type):\(identifier)"
        )
    }
}

