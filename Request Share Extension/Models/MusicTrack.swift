//
//  MusicTrack.swift
//  Request Share Extension
//
//  Created by Jake Bromberg on 11/24/25.
//

import Foundation

struct MusicTrack {
    let service: MusicServiceIdentifier
    let url: URL
    let title: String?
    let artist: String?
    let album: String?
    let identifier: String?
    var artworkURL: URL?
    
    /// Display format: "Track Title - Artist (Album)"
    var displayTitle: String {
        var components: [String] = []
        
        if let title = title {
            components.append(title)
        }
        
        if let artist = artist {
            if components.isEmpty {
                components.append(artist)
            } else {
                components.append("- \(artist)")
            }
        }
        
        if let album = album {
            components.append("(\(album))")
        }
        
        if components.isEmpty {
            return url.absoluteString
        }
        
        return components.joined(separator: " ")
    }
}

enum MusicServiceIdentifier: String {
    case appleMusic = "apple_music"
    case spotify = "spotify"
    case bandcamp = "bandcamp"
    case youtubeMusic = "youtube_music"
    case soundcloud = "soundcloud"
    case unknown = "unknown"
    
    var displayName: String {
        switch self {
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        case .bandcamp: return "Bandcamp"
        case .youtubeMusic: return "YouTube Music"
        case .soundcloud: return "SoundCloud"
        case .unknown: return "Unknown"
        }
    }
}

