//
//  CachingArtworkService.swift
//  Core
//
//  Created by Jake Bromberg on 3/1/25.
//

import Foundation
import Caching
import Core
import Playlist

// TODO: Remove this and replace with `CachingArtworkService`.
extension CacheCoordinator: ArtworkService {
    // This is necessary because calling `value(for:)` on CacheCoordinator was somehow dispatching to
    // the `fetchArtwork(...)` method below.
    func fetchError(for cacheKeyId: String) async throws -> MultisourceArtworkService.Error {
        try await self.value(for: cacheKeyId)
    }
    
    public func fetchArtwork(for playcut: Playcut) async throws -> Image {
        let releaseOrSong = playcut.releaseTitle.flatMap { $0.isEmpty ? nil : $0 } ?? playcut.songTitle
        let cacheKey = "\(playcut.artistName)-\(releaseOrSong)"
        
        let cachedData: Data = try self.data(for: cacheKey)
        guard let artwork = Image(compatibilityData: cachedData) else {
            throw Error.noCachedResult
        }
        
        return artwork
    }
    
    func set(artwork: Image, for id: String, lifespan: TimeInterval) async {
        let artworkData = artwork.pngDataCompatibility
        self.setData(artworkData, for: id, lifespan: lifespan)
    }
}
