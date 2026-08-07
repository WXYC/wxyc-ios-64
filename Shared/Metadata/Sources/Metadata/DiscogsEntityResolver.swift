//
//  DiscogsEntityResolver.swift
//  Metadata
//
//  Resolves Discogs artist/release entities via the backend proxy endpoint.
//
//  Created by Jake Bromberg on 11/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//
//  The proxy request itself is now a thin wrapper over `Core.WXYCProxyClient`
//  (#761): the single `urlSession` field replaces the former dual
//  `WebSession`/`URLSession` fields this type carried solely to branch on
//  whether a token provider existed — `WXYCProxyClient` (via
//  `URLSession.authedData(for:tokenProvider:)`) already sends a plain
//  unauthenticated request when `tokenProvider` is `nil`, so that branch was
//  never needed. `ServiceError.noResults`, borrowed here to signal an
//  unconstructible request URL, is gone too; that case is now
//  `WXYCProxyClient.ProxyError.invalidURL`.
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
    private let client: WXYCProxyClient
    private let cache: CacheCoordinator

    /// Cache lifespan: 30 days (entity names essentially never change)
    private static let cacheLifespan: TimeInterval = 60 * 60 * 24 * 30

    /// Shared instance for convenience. Unauthenticated — carries no
    /// `Authorization` header, so `proxy/entity/resolve` calls made through it
    /// 401. Callers that have a session (i.e. an app target with
    /// `MusicShareKit.authService`) should construct their own instance via
    /// ``init(tokenProvider:)`` instead of reaching for `shared`.
    public static let shared = DiscogsAPIEntityResolver()

    init(
        baseURL: URL = URL(string: "https://api.wxyc.org")!,
        tokenProvider: SessionTokenProvider? = nil,
        urlSession: URLSession = .shared,
        cache: CacheCoordinator = .AlbumArt
    ) {
        self.client = WXYCProxyClient(baseURL: baseURL, session: urlSession, tokenProvider: tokenProvider)
        self.cache = cache
    }

    /// Creates a resolver that authenticates its `proxy/entity/resolve`
    /// requests with the given token provider, so calls don't 401. Mirrors
    /// the app's existing `PlaycutMetadataService(tokenProvider:)` pattern.
    /// `baseURL`, `urlSession`, and `cache` keep their package-internal
    /// defaults.
    public convenience init(tokenProvider: SessionTokenProvider?) {
        // The extra `urlSession:` label disambiguates this delegation from
        // the designated `init(baseURL:tokenProvider:urlSession:cache:)`.
        // Without a second label, `self.init(tokenProvider:)` would resolve
        // to THIS convenience initializer (an exact-arity match Swift
        // prefers over the designated init, which would need three defaults
        // applied), recursing until it crashes.
        self.init(tokenProvider: tokenProvider, urlSession: .shared)
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
                let response: EntityResolveResponse = try await client.get(
                    "proxy/entity/resolve",
                    query: [
                        URLQueryItem(name: "type", value: type),
                        URLQueryItem(name: "id", value: String(id))
                    ]
                )
                return response
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
