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
        let cacheKey = playcut.artworkCacheKey
        
        if let existingTask = inflightTasks[cacheKey],
           let value = await existingTask.value {
            return value
        }
        
        let task = Task<Image?, Never> {
            defer { Task { removeTask(for: cacheKey) } }
            return await scanFetchers(for: playcut)
        }
        
        inflightTasks[cacheKey] = task
        
        if let value = await task.value {
            return value
        } else {
            throw Error.noArtworkAvailable
        }
    }
    
    // MARK: - Private
    
    private func scanFetchers(for playcut: Playcut) async -> Image? {
        let cacheKey = playcut.artworkCacheKey
        let errorCacheKey = "error_\(cacheKey)"

        if let error: Error = try? await self.cacheCoordinator.fetchError(for: errorCacheKey),
           Error.allCases.contains(error) {
        }
        
        // Rotation plays get cached for 30 days; non-rotation plays for 1 day
        let artworkLifespan: TimeInterval = playcut.rotation ? .thirtyDays : .oneDay

        let timer = Core.Timer.start()

        for fetcher in self.fetchers {
            do {
                let artwork = try await fetcher.fetchArtwork(for: playcut)

#if canImport(UIKit) && canImport(Vision)
                guard try await artwork.checkNSFW() == .sfw else {
                    Log(.info, "Inappropriate artwork found for \(cacheKey) using fetcher \(fetcher)")
                    await self.cacheCoordinator.set(value: Error.nsfw, for: errorCacheKey, lifespan: .thirtyDays)

                    return nil
                }
#endif

                await self.cacheCoordinator.set(artwork: artwork, for: cacheKey, lifespan: artworkLifespan)
                return artwork
            } catch {
                Log(.info, "No artwork found for \(cacheKey) using fetcher \(fetcher): \(error)")
            }
        }

        Log(.error, "No artwork found for \(cacheKey) using any fetcher after \(timer.duration()) seconds")
        await self.cacheCoordinator.set(value: Error.noArtworkAvailable, for: errorCacheKey, lifespan: .thirtyDays)

        return nil
    }
    
    private func removeTask(for id: String) {
        inflightTasks[id] = nil
    }
}
