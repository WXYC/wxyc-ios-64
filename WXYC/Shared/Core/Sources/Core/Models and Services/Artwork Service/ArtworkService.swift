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

#if canImport(UIKit) && canImport(Vision)
                guard try await artwork.checkNSFW() == .sfw else {
                    Log(.info, "Inappropriate artwork found for \(playcut.id) using fetcher \(fetcher)")
                    return nil
                }
#endif
                
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
