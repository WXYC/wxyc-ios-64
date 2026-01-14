//
//  MetadataCacheKey.swift
//  Metadata
//
//  Cache key generation for playcut metadata lookups.
//
//  Created by Jake Bromberg on 01/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Core
import Foundation

/// Utility for generating consistent cache keys for metadata at different granularity levels.
///
/// Cache keys are designed to maximize cache hits by caching at the appropriate level:
/// - Artist metadata is keyed by Discogs artist ID (30-day TTL)
/// - Album metadata is keyed by artist+release (7-day TTL)
/// - Streaming links are keyed by artist+song (7-day TTL)
public enum MetadataCacheKey {

    /// Cache key for artist metadata, keyed by Discogs artist ID.
    ///
    /// Artist metadata (bio, Wikipedia link) rarely changes and can be cached for 30 days.
    /// - Parameter discogsId: The Discogs artist ID
    /// - Returns: Cache key in format `artist-{discogsId}`
    public static func artist(discogsId: Int) -> String {
        "artist-\(discogsId)"
    }

    /// Cache key for album metadata, keyed by artist name and release title.
    ///
    /// Album metadata (label, year, Discogs URL) is stable and can be cached for 7 days.
    /// - Parameters:
    ///   - artistName: The artist name
    ///   - releaseTitle: The release/album title (empty string if not available)
    /// - Returns: Cache key in format `album-{artistName}-{releaseTitle}`
    public static func album(artistName: String, releaseTitle: String) -> String {
        let release = releaseTitle.isEmpty ? "unknown" : releaseTitle
        return "album-\(artistName)-\(release)"
    }

    /// Cache key for streaming links, keyed by artist name and song title.
    ///
    /// Streaming links are specific to a song and can be cached for 7 days.
    /// - Parameters:
    ///   - artistName: The artist name
    ///   - songTitle: The song title
    /// - Returns: Cache key in format `streaming-{artistName}-{songTitle}`
    public static func streaming(artistName: String, songTitle: String) -> String {
        "streaming-\(artistName)-\(songTitle)"
    }
}
