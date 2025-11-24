//
//  AppleMusicService.swift
//  MusicShareKit
//
//  Created by Jake Bromberg on 11/24/25.
//

import Foundation

public final class AppleMusicService: MusicService {
    public let identifier: MusicServiceIdentifier = .appleMusic
    
    public init() {}
    
    public func canHandle(url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        let scheme = url.scheme?.lowercased() ?? ""
        
        return host.contains("music.apple.com") || scheme == "music"
    }
    
    public func parse(url: URL) -> MusicTrack? {
        guard canHandle(url: url) else { return nil }
        
        // Handle music:// scheme URLs
        if url.scheme?.lowercased() == "music" {
            // music:// URLs are typically in format: music://album/[id] or music://track/[id]
            let pathComponents = url.pathComponents
            if pathComponents.count >= 3 {
                let type = pathComponents[1] // "album" or "track"
                let id = pathComponents[2]
                return MusicTrack(
                    service: .appleMusic,
                    url: url,
                    title: nil,
                    artist: nil,
                    album: nil,
                    identifier: "\(type):\(id)"
                )
            }
        }
        
        // Handle https://music.apple.com URLs
        // Format: https://music.apple.com/[country]/[type]/[name]/[id]?i=[trackId]
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        
        var title: String?
        var artist: String?
        var album: String?
        var identifier: String?
        
        // Extract track ID from query parameter if present
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let trackId = components.queryItems?.first(where: { $0.name == "i" })?.value {
            identifier = trackId
        }
        
        // Try to extract metadata from path
        // Path format: /[country]/[type]/[name]/[id]
        // Example: /us/album/album-name/1234567890
        if pathComponents.count >= 4 {
            let type = pathComponents[1] // "album", "artist", etc.
            let name = pathComponents[2]
            let id = pathComponents[3]
            
            if identifier == nil {
                identifier = id
            }
            
            // Decode URL-encoded name
            title = name.replacingOccurrences(of: "-", with: " ").capitalized
            
            if type == "album" {
                album = title
            }
        }
        
        return MusicTrack(
            service: .appleMusic,
            url: url,
            title: title,
            artist: artist,
            album: album,
            identifier: identifier
        )
    }
    
    public func fetchArtwork(for track: MusicTrack) async throws -> URL? {
        // Use iTunes Search API to get artwork
        // API: https://itunes.apple.com/lookup?id=[trackId]
        guard let trackId = track.identifier else { return nil }
        
        // Extract numeric ID from identifier (could be "album:123" or just "123")
        let numericId = trackId.components(separatedBy: ":").last ?? trackId
        
        let apiURL = URL(string: "https://itunes.apple.com/lookup?id=\(numericId)")!
        let (data, _) = try await URLSession.shared.data(from: apiURL)
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let results = json?["results"] as? [[String: Any]],
              let firstResult = results.first,
              let artworkUrlString = firstResult["artworkUrl100"] as? String else {
            return nil
        }
        
        // Get higher resolution artwork (600x600 instead of 100x100)
        let highResUrl = artworkUrlString.replacingOccurrences(of: "100x100", with: "600x600")
        return URL(string: highResUrl)
    }
}

