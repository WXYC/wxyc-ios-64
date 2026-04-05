//
//  PlaylistCacheKey.swift
//  Playlist
//
//  Cache key generation for playlist data. Follows the MetadataCacheKey pattern
//  to provide consistent, namespaced cache keys.
//
//  Created by Jake Bromberg on 03/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

/// Utility for generating consistent cache keys for playlist data.
///
/// The playlist cache stores the full playlist response with a 15-minute TTL.
public enum PlaylistCacheKey {

    /// Cache key for the current playlist.
    ///
    /// Only one playlist is cached at a time. The key is static because
    /// the playlist represents the station's current state.
    public static let playlist = "com.wxyc.playlist.cache"
}
