//
//  MusicTrack.swift
//  MusicShareKit
//
//  Created by Jake Bromberg on 11/24/25.
//

import Foundation

public struct MusicTrack: Sendable {
    public let service: MusicServiceIdentifier
    public let url: URL
    public let title: String?
    public let artist: String?
    public let album: String?
    public let identifier: String?
    public var artworkURL: URL?
    
    public init(
        service: MusicServiceIdentifier,
        url: URL,
        title: String?,
        artist: String?,
        album: String?,
        identifier: String?,
        artworkURL: URL? = nil
    ) {
        self.service = service
        self.url = url
        self.title = title
        self.artist = artist
        self.album = album
        self.identifier = identifier
        self.artworkURL = artworkURL
    }
    
    /// Display format: "Track Title - Artist (Album)"
    public var displayTitle: String {
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

public enum MusicServiceIdentifier: String, Sendable {
    case appleMusic = "apple_music"
    case spotify = "spotify"
    case bandcamp = "bandcamp"
    case youtubeMusic = "youtube_music"
    case soundcloud = "soundcloud"
    case unknown = "unknown"
    
    public var displayName: String {
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

