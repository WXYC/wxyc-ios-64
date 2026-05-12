//
//  SemanticIndexService.swift
//  SemanticIndex
//
//  API client for the WXYC semantic-index graph service (explore.wxyc.org).
//  Provides artist search, neighbor lookups, and detail fetching with
//  multi-level caching.
//
//  Created by Jake Bromberg on 04/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Core
import Caching
import Logger
import struct Logger.Category

/// API client for the WXYC semantic-index graph service.
///
/// The semantic-index encodes 22 years of WXYC DJ transition data as a graph.
/// This service provides:
/// - Artist search by name
/// - Neighbor lookups for DJ-validated transitions
/// - Artist detail with streaming service IDs
/// - Preview data with artwork and Apple Music links
///
/// All responses are cached via ``CacheCoordinator`` to reduce redundant API calls.
public actor SemanticIndexService {
    private let baseURL: URL
    private let session: WebSession
    private let cache: CacheCoordinator
    private let errorReporter: any ErrorReporter

    public init(
        baseURL: URL = URL(string: "https://explore.wxyc.org")!,
        errorReporter: any ErrorReporter = ErrorReporting.shared
    ) {
        self.baseURL = baseURL
        self.session = URLSession.shared
        self.cache = .Metadata
        self.errorReporter = errorReporter
    }

    init(
        baseURL: URL = URL(string: "https://explore.wxyc.org")!,
        session: WebSession,
        cache: CacheCoordinator = .Metadata,
        errorReporter: any ErrorReporter = ErrorReporting.shared
    ) {
        self.baseURL = baseURL
        self.session = session
        self.cache = cache
        self.errorReporter = errorReporter
    }

    // MARK: - Public API

    /// Searches for an artist by name in the semantic-index graph.
    ///
    /// - Parameter name: The artist name to search for.
    /// - Returns: The best-matching artist, or `nil` if not found.
    public func searchArtist(name: String) async -> SemanticIndexArtist? {
        let cacheKey = SemanticIndexCacheKey.search(name: name)

        let results: [SemanticIndexArtist]? = await timedOperation(
            context: "searchArtist(\(name))",
            category: .network,
            fallback: nil,
            errorReporter: errorReporter
        ) {
            try await cachedFetch(
                key: cacheKey,
                cache: cache,
                lifespan: .sevenDays,
                fetch: {
                    try await fetchJSON(
                        path: "graph/artists/search",
                        queryItems: [
                            URLQueryItem(name: "q", value: name),
                            URLQueryItem(name: "limit", value: "1"),
                        ]
                    )
                }
            )
        }

        return results?.first
    }

    /// Fetches the top neighbors (DJ transitions) for an artist.
    ///
    /// - Parameters:
    ///   - artistId: The semantic-index artist ID.
    ///   - heat: The heat parameter (0.0 = cool/predictable, 1.0 = hot/surprising). Defaults to 0.0.
    ///   - limit: Maximum number of neighbors to return. Defaults to 3.
    /// - Returns: The neighbor entries, or an empty array on failure.
    public func neighbors(for artistId: Int, heat: Double = 0.0, limit: Int = 3) async -> [SemanticIndexNeighbor] {
        let cacheKey = SemanticIndexCacheKey.neighbors(artistId: artistId, heat: heat)

        return await timedOperation(
            context: "neighbors(\(artistId), heat=\(heat))",
            category: .network,
            fallback: [],
            errorReporter: errorReporter
        ) {
            try await cachedFetch(
                key: cacheKey,
                cache: cache,
                lifespan: .sevenDays,
                fetch: {
                    try await fetchJSON(
                        path: "graph/artists/\(artistId)/neighbors",
                        queryItems: [
                            URLQueryItem(name: "type", value: "djTransition"),
                            URLQueryItem(name: "heat", value: String(heat)),
                            URLQueryItem(name: "limit", value: String(limit)),
                        ]
                    )
                },
                fallback: { [] }
            )
        }
    }

    /// Fetches full detail for an artist, including streaming service IDs.
    ///
    /// - Parameter id: The semantic-index artist ID.
    /// - Returns: The artist detail, or `nil` on failure.
    public func artistDetail(id: Int) async -> SemanticIndexArtistDetail? {
        let cacheKey = SemanticIndexCacheKey.artistDetail(id: id)

        return await timedOperation(
            context: "artistDetail(\(id))",
            category: .network,
            fallback: nil,
            errorReporter: errorReporter
        ) {
            try await cachedFetch(
                key: cacheKey,
                cache: cache,
                lifespan: .thirtyDays,
                fetch: {
                    try await fetchJSON(
                        path: "graph/artists/\(id)",
                        queryItems: []
                    )
                }
            )
        }
    }

    /// Fetches preview data (artwork, track, album URL) for an artist.
    ///
    /// - Parameter artistId: The semantic-index artist ID.
    /// - Returns: The preview data, or `nil` on failure.
    public func preview(for artistId: Int) async -> SemanticIndexPreview? {
        let cacheKey = SemanticIndexCacheKey.preview(id: artistId)

        return await timedOperation(
            context: "preview(\(artistId))",
            category: .network,
            fallback: nil,
            errorReporter: errorReporter
        ) {
            try await cachedFetch(
                key: cacheKey,
                cache: cache,
                lifespan: .thirtyDays,
                fetch: {
                    try await fetchJSON(
                        path: "graph/artists/\(artistId)/preview",
                        queryItems: []
                    )
                }
            )
        }
    }

    /// Convenience method that chains search + neighbors to get recommendations for an artist by name.
    ///
    /// - Parameter artistName: The artist name to search for.
    /// - Returns: The top neighbor entries, or an empty array if the artist is not in the graph.
    public func recommendations(forArtistNamed artistName: String) async -> [SemanticIndexNeighbor] {
        guard let artist = await searchArtist(name: artistName) else {
            return []
        }

        return await neighbors(for: artist.id)
    }

    // MARK: - Network

    private func fetchJSON<T: Codable & Sendable>(path: String, queryItems: [URLQueryItem]) async throws -> T {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!

        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw SemanticIndexError.invalidURL
        }

        let data = try await session.data(from: url)
        return try JSONDecoder.shared.decode(T.self, from: data)
    }
}

// MARK: - Errors

extension SemanticIndexService {
    enum SemanticIndexError: Error {
        case invalidURL
    }
}
