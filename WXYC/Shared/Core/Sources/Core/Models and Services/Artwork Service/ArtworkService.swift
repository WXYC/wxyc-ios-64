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
import OpenNSFW
import Logger

protocol ArtworkFetcher: Sendable {
    func fetchArtwork(for playcut: Playcut) async throws -> UIImage
}

// TODO: Rename to CompositeArtworkService and conform it to `ArtworkFetcher`
public final actor ArtworkService {
    enum Error: Codable, CaseIterable {
        case noArtworkAvailable
        case nsfw
    }
    
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
        let cacheId = playcut.releaseTitle ?? playcut.songTitle
        if let error: Error = try? await self.cacheCoordinator.fetchError(for: playcut),
           Error.allCases.contains(error) {
            Log(.info, "Previous attempt to find artwork errored \(error) for \(cacheId), skipping")
        }
        
        let timer = Timer.start()
        
        for fetcher in self.fetchers {
            do {
                let artwork = try await fetcher.fetchArtwork(for: playcut)
                
                Log(.info, "Artwork \(artwork) found for \(cacheId) using fetcher \(fetcher) after \(timer.duration()) seconds")

#if canImport(UIKit) && canImport(Vision)
                guard try await artwork.checkNSFW() == .sfw else {
                    Log(.info, "Inappropriate artwork found for \(cacheId) using fetcher \(fetcher)")
                    await self.cacheCoordinator.set(value: Error.nsfw, for: cacheId, lifespan: .thirtyDays)
                    
                    return nil
                }
#endif
                
                await self.cacheCoordinator.set(artwork: artwork, for: cacheId)
                return artwork
            } catch {
                Log(.info, "No artwork found for \(cacheId) using fetcher \(fetcher): \(error)")
            }
        }
        
        Log(.error, "No artwork found for \(cacheId) using any fetcher")
        await self.cacheCoordinator.set(value: Error.noArtworkAvailable, for: cacheId, lifespan: .thirtyDays)
        
        return nil
    }
}
