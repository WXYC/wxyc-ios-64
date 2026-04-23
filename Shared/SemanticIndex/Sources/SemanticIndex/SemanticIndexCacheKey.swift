//
//  SemanticIndexCacheKey.swift
//  SemanticIndex
//
//  Cache key generation for semantic-index API responses.
//
//  Created by Jake Bromberg on 04/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Utility for generating consistent cache keys for semantic-index API responses.
///
/// Cache keys are prefixed with `si-` to avoid collisions with metadata cache keys.
/// Each endpoint has its own key format and TTL:
/// - Search: 7-day TTL (artist name to ID mapping, stable between graph rebuilds)
/// - Neighbors: 7-day TTL (transition weights update with pipeline runs)
/// - Artist detail: 30-day TTL (streaming IDs are very stable)
/// - Preview: 30-day TTL (iTunes data is very stable)
public enum SemanticIndexCacheKey {

    /// Cache key for artist search results, keyed by artist name.
    ///
    /// - Parameter name: The artist name used in the search query.
    /// - Returns: Cache key in format `si-search-{name}`
    public static func search(name: String) -> String {
        "si-search-\(name)"
    }

    /// Cache key for artist neighbors, keyed by artist ID and heat parameter.
    ///
    /// - Parameters:
    ///   - artistId: The semantic-index artist ID.
    ///   - heat: The heat parameter used in the query.
    /// - Returns: Cache key in format `si-neighbors-{artistId}-{heat}`
    public static func neighbors(artistId: Int, heat: Double) -> String {
        "si-neighbors-\(artistId)-\(heat)"
    }

    /// Cache key for artist detail, keyed by artist ID.
    ///
    /// - Parameter id: The semantic-index artist ID.
    /// - Returns: Cache key in format `si-artist-{id}`
    public static func artistDetail(id: Int) -> String {
        "si-artist-\(id)"
    }

    /// Cache key for artist preview data, keyed by artist ID.
    ///
    /// - Parameter id: The semantic-index artist ID.
    /// - Returns: Cache key in format `si-preview-{id}`
    public static func preview(id: Int) -> String {
        "si-preview-\(id)"
    }
}
