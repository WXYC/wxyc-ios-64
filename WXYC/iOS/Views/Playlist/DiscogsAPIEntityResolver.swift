//
//  DiscogsAPIEntityResolver.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/27/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
import Secrets
import Core

/// Resolves Discogs entity IDs by calling the Discogs API
final class DiscogsAPIEntityResolver: DiscogsEntityResolver, Sendable {
    private let session: WebSession
    private let decoder: JSONDecoder
    private let cache: CacheCoordinator
    
    /// Cache lifespan: 30 days (entity names essentially never change)
    private static let cacheLifespan: TimeInterval = 60 * 60 * 24 * 30
    
    /// Shared instance for convenience
    static let shared = DiscogsAPIEntityResolver()
    
    init(session: WebSession = URLSession.shared, cache: CacheCoordinator = .AlbumArt) {
        self.session = session
        self.decoder = JSONDecoder()
        self.cache = cache
    }
    
    func resolveArtist(id: Int) async throws -> String {
        let cacheKey = "discogs-artist-\(id)"
        
        // Check cache first
        if let cached: String = try? await cache.value(for: cacheKey) {
            return cached
        }
        
        let url = makeURL(path: "/artists/\(id)")
        let data = try await session.data(from: url)
        let artist = try decoder.decode(DiscogsArtist.self, from: data)
        
        // Cache the result
        await cache.set(value: artist.name, for: cacheKey, lifespan: Self.cacheLifespan)
        
        return artist.name
    }
    
    func resolveRelease(id: Int) async throws -> String {
        let cacheKey = "discogs-release-\(id)"
        
        // Check cache first
        if let cached: String = try? await cache.value(for: cacheKey) {
            return cached
        }
        
        let url = makeURL(path: "/releases/\(id)")
        let data = try await session.data(from: url)
        let release = try decoder.decode(DiscogsRelease.self, from: data)
        
        // Cache the result
        await cache.set(value: release.title, for: cacheKey, lifespan: Self.cacheLifespan)
        
        return release.title
    }
    
    func resolveMaster(id: Int) async throws -> String {
        let cacheKey = "discogs-master-\(id)"
        
        // Check cache first
        if let cached: String = try? await cache.value(for: cacheKey) {
            return cached
        }
        
        let url = makeURL(path: "/masters/\(id)")
        let data = try await session.data(from: url)
        let master = try decoder.decode(DiscogsMaster.self, from: data)
        
        // Cache the result
        await cache.set(value: master.title, for: cacheKey, lifespan: Self.cacheLifespan)
        
        return master.title
    }
    
    private func makeURL(path: String) -> URL {
        var components = URLComponents(string: "https://api.discogs.com")!
        components.path = path
        components.queryItems = [
            URLQueryItem(name: "key", value: Secrets.discogsApiKeyV2_5),
            URLQueryItem(name: "secret", value: Secrets.discogsApiSecretV2_5)
        ]
        return components.url!
    }
}

// MARK: - Discogs API Response Models

private struct DiscogsArtist: Codable, Sendable {
    let id: Int
    let name: String
}

private struct DiscogsRelease: Codable, Sendable {
    let id: Int
    let title: String
}

private struct DiscogsMaster: Codable, Sendable {
    let id: Int
    let title: String
}
