//
//  DiscogsAPIEntityResolver.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/27/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
import Secrets

/// Resolves Discogs entity IDs by calling the Discogs API
final class DiscogsAPIEntityResolver: DiscogsEntityResolver, @unchecked Sendable {
    private let session: URLSession
    private let decoder: JSONDecoder
    
    // Cache resolved entities to avoid redundant API calls
    private var artistCache: [Int: String] = [:]
    private var releaseCache: [Int: String] = [:]
    private var masterCache: [Int: String] = [:]
    private let cacheQueue = DispatchQueue(label: "com.wxyc.entityResolver.cache")
    
    /// Shared instance for convenience
    static let shared = DiscogsAPIEntityResolver()
    
    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
    }
    
    func resolveArtist(id: Int) async throws -> String {
        // Check cache first
        if let cached = cacheQueue.sync(execute: { artistCache[id] }) {
            return cached
        }
        
        let url = makeURL(path: "/artists/\(id)")
        let (data, _) = try await session.data(from: url)
        let artist = try decoder.decode(DiscogsArtist.self, from: data)
        
        // Cache the result
        cacheQueue.sync { artistCache[id] = artist.name }
        
        return artist.name
    }
    
    func resolveRelease(id: Int) async throws -> String {
        // Check cache first
        if let cached = cacheQueue.sync(execute: { releaseCache[id] }) {
            return cached
        }
        
        let url = makeURL(path: "/releases/\(id)")
        let (data, _) = try await session.data(from: url)
        let release = try decoder.decode(DiscogsRelease.self, from: data)
        
        // Cache the result
        cacheQueue.sync { releaseCache[id] = release.title }
        
        return release.title
    }
    
    func resolveMaster(id: Int) async throws -> String {
        // Check cache first
        if let cached = cacheQueue.sync(execute: { masterCache[id] }) {
            return cached
        }
        
        let url = makeURL(path: "/masters/\(id)")
        let (data, _) = try await session.data(from: url)
        let master = try decoder.decode(DiscogsMaster.self, from: data)
        
        // Cache the result
        cacheQueue.sync { masterCache[id] = master.title }
        
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
