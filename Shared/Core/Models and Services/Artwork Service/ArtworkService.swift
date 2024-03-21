//
//  ArtworkService.swift
//  Core
//
//  Created by Jake Bromberg on 12/5/18.
//  Copyright © 2018 WXYC. All rights reserved.
//

import Foundation
import UIKit
import Combine

public final actor ArtworkService {
    public static let shared = ArtworkService(fetchers: [
        DiscogsArtworkFetcher(),
        LastFMArtworkFetcher(),
        iTunesArtworkFetcher(),
    ])

    private let fetchers: [ArtworkFetcher]
    private let cacheCoordinator: CacheCoordinator
    
    private init(fetchers: [ArtworkFetcher], cacheCoordinator: CacheCoordinator = .AlbumArt) {
        self.fetchers = fetchers
        self.cacheCoordinator = cacheCoordinator
    }

    public func getArtwork(for playcut: Playcut) async -> UIImage? {
        if let artwork = try? await self.cacheCoordinator.fetchArtwork(for: playcut) {
            return artwork
        }
        
        for fetcher in self.fetchers {
            do {
                let artwork = try await fetcher.fetchArtwork(for: playcut)
                guard try await artwork.checkNSFW() == .sfw else {
                    return nil
                }
                await self.cacheCoordinator.set(artwork: artwork, for: playcut)
                return artwork
            } catch {
                print(">>> No artwork found for \(playcut) using fetcher \(fetcher): \(error)")
            }
        }
        
        print(">>> No artwork found for \(playcut) using any fetcher")
        return nil
    }
}

protocol ArtworkFetcher {
    func fetchArtwork(for playcut: Playcut) async throws -> UIImage
}

extension CacheCoordinator: ArtworkFetcher {
    func fetchArtwork(for playcut: Playcut) async throws -> UIImage {
        let cachedData: Data = try await self.value(for: playcut)
        guard let artwork = UIImage(data: cachedData) else {
            throw ServiceErrors.noCachedResult
        }
        
        return artwork
    }
    
    func set(artwork: UIImage, for playcut: Playcut) async {
        let artworkData = artwork.pngData()
        set(value: artworkData, for: playcut, lifespan: .distantFuture)
    }
}

internal final class CachingArtworkFetcher: ArtworkFetcher {
    private let cacheCoordinator: CacheCoordinator
    private let fetcher: ArtworkFetcher
    
    internal init(
        fetcher: ArtworkFetcher,
        cacheCoordinator: CacheCoordinator = .AlbumArt
    ) {
        self.fetcher = fetcher
        self.cacheCoordinator = cacheCoordinator
    }
    
    internal func fetchArtwork(for playcut: Playcut) async throws -> UIImage {
        let artwork = try await self.fetcher.fetchArtwork(for: playcut)
        await self.cacheCoordinator.set(value: artwork.pngData(), for: playcut, lifespan: .distantFuture)
        
        return artwork
    }
}
