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

    /// Cache key for the current playlist as fetched by `version`.
    ///
    /// One entry per API version, deliberately: `chronOrderID` is persisted
    /// with every entry, and the two versions write it at scales nine orders
    /// of magnitude apart — v1 decodes the row id off the wire, while v2
    /// derives the packed `(show_id, play_order)` composite (magnitudes in
    /// `FlowsheetConverter.chronOrderID(showID:playOrder:id:)`'s doc).
    /// Sessions resolving different versions share this storage
    /// (a flag miss, an offline launch, a DebugPanel switch, and the widget
    /// process — which resolves independently of the app — are all real v1
    /// writers), so a shared key would let a v1 session seed the baseline a
    /// v2 session loads before consuming SSE frames. One live-fs update
    /// frame later, `PlaylistService.upsertPlaycut` hands a single stale row
    /// a packed key and with it the head of the timeline and
    /// `currentPlaycut` — a song from an hour ago on the lock screen.
    ///
    /// Both keys are also fresh relative to the pre-#839
    /// `com.wxyc.playlist.cache`, whose entries hold the old id-scale scheme
    /// under either version; that orphaned entry ages out on its 15-minute
    /// TTL. This is narrower than bumping
    /// `CacheMigrationManager.cacheSchemaVersion`, which is the right lever
    /// when a cached *Codable shape* changes — a bump purges every cache in
    /// scope, including re-fetchable artwork and metadata. Here the shape is
    /// unchanged and only this entry's *value scheme* is version-dependent,
    /// so the isolation lives in the key.
    public static func playlist(for version: PlaylistAPIVersion) -> String {
        switch version {
        case .v1: "com.wxyc.playlist.cache.v1"
        case .v2: "com.wxyc.playlist.cache.v2"
        }
    }
}
