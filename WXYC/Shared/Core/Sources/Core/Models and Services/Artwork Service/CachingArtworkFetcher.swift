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
    // This is necessary because calling `value(for:)` on CacheCoordinator was somehow dispatching to
    // the `fetchArtwork(...)` method below.
    func fetchError(for cacheKeyId: String) async throws -> ArtworkService.Error {
        try await self.value(for: cacheKeyId)
    }
    
    func fetchArtwork(for playcut: Playcut) async throws -> UIImage {
        let cachedData: Data = try await self.value(for: playcut.releaseTitle ?? playcut.songTitle)
        guard let artwork = UIImage(data: cachedData) else {
            throw Error.noCachedResult
        }
        
        return artwork
    }
    
    func set(artwork: UIImage, for id: String) async {
        let artworkData = artwork.pngData()
        self.set(value: artworkData, for: id, lifespan: .thirtyDays)
    }
}
