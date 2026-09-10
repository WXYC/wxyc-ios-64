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
    /// Still version-suffixed after the v1 path was removed (#262), and
    /// deliberately so: the suffix is what kept a v1-resolving session from
    /// seeding a v2 session's baseline back when both existed, because the two
    /// wrote `chronOrderID` at scales nine orders of magnitude apart. Renaming
    /// it now would orphan every warm entry on upgrade for no gain — the key
    /// is private to this build and its only job is to be stable.
    ///
    /// The pre-#839 `com.wxyc.playlist.cache` and the `.v1` entry both age out
    /// on their own 15-minute TTL. That is narrower than bumping
    /// `CacheMigrationManager.cacheSchemaVersion`, which is the right lever
    /// when a cached *Codable shape* changes — a bump purges every cache in
    /// scope, including re-fetchable artwork and metadata.
    public static let playlist = "com.wxyc.playlist.cache.v2"
}
