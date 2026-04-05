//
//  DiscogsEntityResolver.swift
//  Metadata
//
//  Resolves Discogs artist/release entities via the backend proxy endpoint.
//
//  Created by Jake Bromberg on 11/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
import Core
import Caching

/// Protocol for resolving Discogs entity IDs to their names
public protocol DiscogsEntityResolver: Sendable {
    func resolveArtist(id: Int) async throws -> String
    func resolveRelease(id: Int) async throws -> String
    func resolveMaster(id: Int) async throws -> String
}

/// Resolves Discogs entity IDs by calling the backend proxy endpoint
public final class DiscogsAPIEntityResolver: DiscogsEntityResolver, Sendable {
    private let baseURL: URL
    private let tokenProvider: SessionTokenProvider?
    private let session: WebSession
    private let cache: CacheCoordinator

    /// Cache lifespan: 30 days (entity names essentially never change)
    private static let cacheLifespan: TimeInterval = 60 * 60 * 24 * 30

    /// Shared instance for convenience
    public static let shared = DiscogsAPIEntityResolver()

    init(
        baseURL: URL = URL(string: "https://api.wxyc.org")!,
        tokenProvider: SessionTokenProvider? = nil,
        session: WebSession = URLSession.shared,
        cache: CacheCoordinator = .AlbumArt
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.session = session
        self.cache = cache
    }

    public func resolveArtist(id: Int) async throws -> String {
        try await resolve(type: "artist", id: id)
    }

    public func resolveRelease(id: Int) async throws -> String {
        try await resolve(type: "release", id: id)
    }

    public func resolveMaster(id: Int) async throws -> String {
        try await resolve(type: "master", id: id)
    }

    private func resolve(type: String, id: Int) async throws -> String {
        let cacheKey = MetadataCacheKey.discogsEntity(type: type, id: id)

        return try await cachedFetch(
            key: cacheKey,
            cache: cache,
            lifespan: Self.cacheLifespan,
            fetch: {
                var components = URLComponents(url: baseURL.appending(path: "proxy/entity/resolve"), resolvingAgainstBaseURL: false)!
                components.queryItems = [
                    URLQueryItem(name: "type", value: type),
                    URLQueryItem(name: "id", value: String(id))
                ]

                guard let url = components.url else {
                    throw ServiceError.noResults
                }

                let data: Data
                if let tokenProvider {
                    let token = try await tokenProvider.token()
                    var request = URLRequest(url: url)
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    let (responseData, _) = try await URLSession.shared.data(for: request)
                    data = responseData
                } else {
                    data = try await session.data(from: url)
                }

                return try JSONDecoder.shared.decode(EntityResolveResponse.self, from: data)
            },
            transform: { $0.name }
        )
    }
}

// MARK: - Backend Response Model

private struct EntityResolveResponse: Codable, Sendable {
    let name: String
    let type: String
    let id: Int
}
