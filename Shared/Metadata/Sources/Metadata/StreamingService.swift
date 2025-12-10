//
//  StreamingService.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI

public enum StreamingService {
    case spotify
    case appleMusic
    case youtubeMusic
    case bandcamp
    case soundcloud
    
    public var name: String {
        switch self {
        case .spotify: return "Spotify"
        case .appleMusic: return "Apple Music"
        case .youtubeMusic: return "YouTube Music"
        case .bandcamp: return "Bandcamp"
        case .soundcloud: return "SoundCloud"
        }
    }
    
    public var iconName: String {
        switch self {
        case .spotify: return "spotify"
        case .appleMusic: return "applemusic"
        case .youtubeMusic: return "youtubemusic"
        case .bandcamp: return "bandcamp"
        case .soundcloud: return "soundcloud"
        }
    }
    
    public var systemIcon: String {
        switch self {
        case .spotify: return "music.note"
        case .appleMusic: return "music.note"
        case .youtubeMusic: return "play.rectangle.fill"
        case .bandcamp: return "music.quarternote.3"
        case .soundcloud: return "waveform"
        }
    }
    
    public var color: Color {
        switch self {
        case .spotify: return Color(red: 0.11, green: 0.73, blue: 0.33)
        case .appleMusic: return Color(red: 0.98, green: 0.18, blue: 0.33)
        case .youtubeMusic: return Color(red: 1.0, green: 0.0, blue: 0.0)
        case .bandcamp: return Color(red: 0.38, green: 0.76, blue: 0.87)
        case .soundcloud: return Color(red: 1.0, green: 0.33, blue: 0.0)
        }
    }
    
    public var hasCustomIcon: Bool {
        switch self {
        case .spotify, .appleMusic, .bandcamp: return true
        case .youtubeMusic, .soundcloud: return false
        }
    }
    
    /// Services that link to search pages (not direct deep links) should open in Safari
    /// to preserve query parameters that would be lost via Universal Links
    public var opensInBrowser: Bool {
        switch self {
        case .spotify, .appleMusic, .youtubeMusic, .bandcamp: return false
        case .soundcloud: return true
        }
    }
}

