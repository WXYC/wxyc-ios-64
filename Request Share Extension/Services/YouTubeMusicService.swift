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
}

