//
//  CachingArtworkFetcher.swift
//  Core
//
//  Created by Jake Bromberg on 3/1/25.
//

import Foundation
import UIKit

// TODO: Remove this and replace with `CachingArtworkFetcher`.
extension CacheCoordinator: ArtworkFetcher {
    func fetchArtwork(for playcut: Playcut) async throws -> UIImage {
        let cachedData: Data = try await self.value(for: playcut)
        guard let artwork = UIImage(data: cachedData) else {
            throw ServiceError.noCachedResult
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
