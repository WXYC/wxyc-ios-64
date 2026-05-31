//
//  MusicService.swift
//  Core
//
//  Canonical identifier for the music streaming services the app understands.
//  Used by Metadata for streaming-link UI and by MusicShareKit for share-sheet URL parsing.
//
//  Created by Jake Bromberg on 05/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Identifies a music streaming service.
///
/// The raw `String` values are stable and used for serialization (e.g. analytics payloads,
/// JSON contracts). The `unknown` case is a defensive default for URLs that cannot be
/// attributed to a known service.
public enum MusicService: String, Sendable, CaseIterable, Codable {
    case appleMusic = "apple_music"
    case spotify = "spotify"
    case bandcamp = "bandcamp"
    case youtubeMusic = "youtube_music"
    case soundcloud = "soundcloud"
    case unknown = "unknown"

    /// Human-readable service name suitable for UI labels and donated intent metadata.
    public var displayName: String {
        switch self {
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        case .bandcamp: "Bandcamp"
        case .youtubeMusic: "YouTube Music"
        case .soundcloud: "SoundCloud"
        case .unknown: "Unknown"
        }
    }
}
