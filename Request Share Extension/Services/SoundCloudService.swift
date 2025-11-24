//
//  SoundCloudService.swift
//  Request Share Extension
//
//  Created by Jake Bromberg on 11/24/25.
//

import Foundation

class SoundCloudService: MusicService {
    let identifier: MusicServiceIdentifier = .soundcloud
    
    func canHandle(url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host.contains("soundcloud.com")
    }
    
    func parse(url: URL) -> MusicTrack? {
        guard canHandle(url: url) else { return nil }
        
        // SoundCloud URLs format:
        // https://soundcloud.com/[artist]/[track-name]
        // https://soundcloud.com/[artist]/[track-name]/[optional-slug]
        
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        
        var title: String?
        var artist: String?
        var identifier: String?
        
        if pathComponents.count >= 2 {
            artist = pathComponents[0].replacingOccurrences(of: "-", with: " ").capitalized
            title = pathComponents[1].replacingOccurrences(of: "-", with: " ").capitalized
            
            // Use the full path as identifier
            identifier = pathComponents.joined(separator: "/")
        }
        
        return MusicTrack(
            service: .soundcloud,
            url: url,
            title: title,
            artist: artist,
            album: nil,
            identifier: identifier
        )
    }
}

