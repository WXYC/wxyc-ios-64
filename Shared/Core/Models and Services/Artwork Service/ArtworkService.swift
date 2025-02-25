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

// TODO: Rename to CompositeArtworkService and conform it to `ArtworkFetcher`
public final actor ArtworkService {
    public static let shared = ArtworkService(fetchers: [
        CacheCoordinator.AlbumArt,
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
        for fetcher in self.fetchers {
            do {
                let artwork = try await fetcher.fetchArtwork(for: playcut)
                Log(.info, "Artwork found for \(playcut.id) using fetcher \(fetcher)")

                guard try await artwork.checkNSFW() == .sfw else {
                    Log(.info, "Inappropriate artwork found for \(playcut.id) using fetcher \(fetcher)")
                    return nil
                }
                
                await self.cacheCoordinator.set(artwork: artwork, for: playcut)
                return artwork
            } catch {
                Log(.error, "No artwork found for \(playcut.id) using fetcher \(fetcher): \(error)")
            }
        }
        
        Log(.error, "No artwork found for \(playcut.id) using any fetcher")
        return nil
    }
}

protocol ArtworkFetcher: Sendable {
    func fetchArtwork(for playcut: Playcut) async throws -> UIImage
}

// TODO: Remove this and replace with `CachingArtworkFetcher`.
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
        self.set(value: artworkData, for: playcut, lifespan: .oneDay)
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
        await self.cacheCoordinator.set(value: artwork.pngData(), for: playcut, lifespan: .oneDay)
        
        return artwork
    }
}
