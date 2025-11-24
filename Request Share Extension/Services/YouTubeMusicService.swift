//
//  YouTubeMusicService.swift
//  Request Share Extension
//
//  Created by Jake Bromberg on 11/24/25.
//

import Foundation

class YouTubeMusicService: MusicService {
    let identifier: MusicServiceIdentifier = .youtubeMusic
    
    func canHandle(url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host.contains("music.youtube.com") || 
               (host.contains("youtube.com") && url.path.contains("/watch")) ||
               host.contains("youtu.be")
    }
    
    func parse(url: URL) -> MusicTrack? {
        guard canHandle(url: url) else { return nil }
        
        var videoId: String?
        
        // Handle youtu.be short URLs
        // Format: https://youtu.be/VIDEO_ID
        if url.host?.lowercased() == "youtu.be" {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !path.isEmpty {
                videoId = path
            }
        } else {
            // Handle youtube.com and music.youtube.com URLs
            // Format: https://music.youtube.com/watch?v=VIDEO_ID
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                // Try v parameter first (standard)
                if let vParam = components.queryItems?.first(where: { $0.name == "v" })?.value {
                    videoId = vParam
                }
                // Some URLs might use different formats
                else if let path = components.path.components(separatedBy: "/").last, !path.isEmpty {
                    videoId = path
                }
            }
        }
        
        guard let id = videoId else { return nil }
        
        return MusicTrack(
            service: .youtubeMusic,
            url: url,
            title: nil,
            artist: nil,
            album: nil,
            identifier: id
        )
    }
    
    func fetchArtwork(for track: MusicTrack) async throws -> URL? {
        // YouTube has a predictable thumbnail URL pattern
        // https://img.youtube.com/vi/[VIDEO_ID]/maxresdefault.jpg (high res)
        // https://img.youtube.com/vi/[VIDEO_ID]/hqdefault.jpg (fallback)
        guard let videoId = track.identifier else { return nil }
        
        // Try high-res first, fall back to HQ if not available
        let highResUrl = URL(string: "https://img.youtube.com/vi/\(videoId)/maxresdefault.jpg")!
        
        // Check if high-res exists by making a HEAD request
        var request = URLRequest(url: highResUrl)
        request.httpMethod = "HEAD"
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
            return highResUrl
        }
        
        // Fall back to HQ default
        return URL(string: "https://img.youtube.com/vi/\(videoId)/hqdefault.jpg")
    }
}

