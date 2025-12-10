//
//  ArtworkService.swift
//  Core
//
//  Created by Jake Bromberg on 12/5/18.
//  Copyright © 2018 WXYC. All rights reserved.
//

import Foundation
import Combine
import OpenNSFW
import Logger
import Caching
import Playlist
import Core

public protocol ArtworkService: Sendable {
    func fetchArtwork(for playcut: Playcut) async throws -> Image
}

// TODO: Rename to CompositeArtworkService and conform it to `ArtworkService`
public final actor MultisourceArtworkService: ArtworkService {
    enum Error: Swift.Error, Codable, CaseIterable {
        case noArtworkAvailable
        case nsfw
    }

    private let fetchers: [ArtworkService]
    private let cacheCoordinator: CacheCoordinator
    private var inflightTasks: [String: Task<Image?, Never>] = [:]

    // Public convenience initializer with default fetchers
    public init() {
        self.init(
            fetchers: [
                CacheCoordinator.AlbumArt,
                DiscogsArtworkService(),
                LastFMArtworkService(),
                iTunesArtworkService(),
            ],
            cacheCoordinator: .AlbumArt
        )
    }

    // Internal initializer for dependency injection
    init(
        fetchers: [any ArtworkService],
        cacheCoordinator: CacheCoordinator
    ) {
        self.fetchers = fetchers
        self.cacheCoordinator = cacheCoordinator
    }

    public func fetchArtwork(for playcut: Playcut) async throws -> Image {
        let id = playcut.releaseTitle ?? playcut.songTitle
        
        if let existingTask = inflightTasks[id],
           let value = await existingTask.value {
            return value
        }
        
        let task = Task<Image?, Never> {
            defer { Task { removeTask(for: id) } }
            return await scanFetchers(for: playcut)
        }
        
        inflightTasks[id] = task
        
        if let value = await task.value {
            return value
        } else {
            throw Error.noArtworkAvailable
        }
    }
    
    // MARK: - Private
    
    private func scanFetchers(for playcut: Playcut) async -> Image? {
        let cacheKeyId = "\(playcut.releaseTitle ?? playcut.songTitle)"
        let errorCacheKeyId = "error_\(playcut.releaseTitle ?? playcut.songTitle)"

        if let error: Error = try? await self.cacheCoordinator.fetchError(for: errorCacheKeyId),
           Error.allCases.contains(error) {
            Log(.info, "Previous attempt to find artwork errored \(error) for \(errorCacheKeyId), skipping")
        }
        
        let timer = Core.Timer.start()
        
        for fetcher in self.fetchers {
            do {
                let artwork = try await fetcher.fetchArtwork(for: playcut)
                
                Log(.info, "Artwork \(artwork) found for \(cacheKeyId) using fetcher \(fetcher) after \(timer.duration()) seconds")

#if canImport(UIKit) && canImport(Vision)
                guard try await artwork.checkNSFW() == .sfw else {
                    Log(.info, "Inappropriate artwork found for \(cacheKeyId) using fetcher \(fetcher)")
                    await self.cacheCoordinator.set(value: Error.nsfw, for: errorCacheKeyId, lifespan: .thirtyDays)
                    
                    return nil
                }
#endif
                
                await self.cacheCoordinator.set(artwork: artwork, for: cacheKeyId)
                return artwork
            } catch {
                Log(.info, "No artwork found for \(cacheKeyId) using fetcher \(fetcher): \(error)")
            }
        }
        
        Log(.error, "No artwork found for \(cacheKeyId) using any fetcher after \(timer.duration()) seconds")
        await self.cacheCoordinator.set(value: Error.noArtworkAvailable, for: errorCacheKeyId, lifespan: .thirtyDays)
        
        return nil
    }
    
    private func removeTask(for id: String) {
        inflightTasks[id] = nil
    }
}
