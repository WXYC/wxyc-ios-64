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
    
    var displayTitle: String {
        if let title = title, let artist = artist {
            return "\(title) - \(artist)"
        } else if let title = title {
            return title
        } else if let artist = artist {
            return artist
        } else {
            return url.absoluteString
        }
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

