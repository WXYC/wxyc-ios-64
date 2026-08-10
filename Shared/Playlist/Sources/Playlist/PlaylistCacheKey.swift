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
    ///
    /// The `.v2` suffix is a one-time invalidation for #839, not a versioning
    /// scheme. `chronOrderID` is persisted with each entry, and a playlist
    /// cached by a pre-#839 build holds the old scheme (the key *was* the row
    /// id, ~5.3e6) while this build derives the packed composite (~8.4e15).
    /// The two can coexist in one array: `PlaylistService.upsertPlaycut`
    /// rewrites a single row from an SSE frame, so an enrichment arriving
    /// before the first poll completes would give one old row a packed key and
    /// send it straight to the head of the timeline — and to
    /// `currentPlaycut`, so the lock screen would name a song from an hour
    /// ago. A 15-minute cache of a public feed that refetches on launch is
    /// cheap to drop once; a wrong now-playing on every upgrading device is
    /// not.
    public static let playlist = "com.wxyc.playlist.cache.v2"
}
