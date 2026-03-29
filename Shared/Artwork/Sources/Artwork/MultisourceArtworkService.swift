//
//  MultisourceArtworkService.swift
//  Artwork
//
//  Aggregates multiple artwork sources (iTunes, Last.fm, Discogs) with
//  caching and NSFW filtering. Tries sources in order until artwork is found.
//
//  Created by Jake Bromberg on 04/12/23.
//  Copyright © 2023 WXYC. All rights reserved.
//

import Foundation
import Combine
import Logger
import Caching
import Playlist
import Core
import ImageIO

public protocol ArtworkService: Sendable {
    func fetchArtwork(for playcut: Playcut) async throws -> CGImage
}

/// Creates a CGImage from raw image data using ImageIO.
/// This avoids UIImage and its MainActor isolation.
public func createCGImage(from data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
        return nil
    }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

#if canImport(UIKit)
import UIKit

public extension CGImage {
    /// Converts the CGImage to a UIImage.
    /// Safe to call from any thread - UIImage(cgImage:) is thread-safe.
    func toUIImage() -> UIImage {
        UIImage(cgImage: self)
    }
}
#endif

// TODO: Rename to CompositeArtworkService and conform it to `ArtworkService`
public final actor MultisourceArtworkService: ArtworkService {
    enum Error: Swift.Error, Codable, CaseIterable {
        case noArtworkAvailable
        case nsfw
    }

    private let fetchers: [ArtworkService]
    private let cacheCoordinator: CacheCoordinator
    private var inflightTasks: [String: Task<CGImage?, Never>] = [:]

    // Public convenience initializer with default fetchers.
    // The backend proxy now handles the full fallback chain (Discogs → Last.fm → iTunes)
    // and NSFW classification server-side, so DiscogsArtworkService is the only remote fetcher.
    public init() {
        self.init(
            fetchers: [
                CacheCoordinator.AlbumArt,
                DiscogsArtworkService(),
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

    public func fetchArtwork(for playcut: Playcut) async throws -> CGImage {
        let cacheKey = playcut.artworkCacheKey

        if let existingTask = inflightTasks[cacheKey],
           let value = await existingTask.value {
            return value
        }

        let task = Task<CGImage?, Never> {
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

    private func scanFetchers(for playcut: Playcut) async -> CGImage? {
        let cacheKey = playcut.artworkCacheKey
        let errorCacheKey = "error_\(cacheKey)"

        if let cachedError: Error = try? await self.cacheCoordinator.fetchError(for: errorCacheKey),
           Error.allCases.contains(cachedError) {
            Log(.info, category: .artwork, "Cached error for \(cacheKey): \(cachedError)")
            return nil
        }

        // Rotation plays get cached for 30 days; non-rotation plays for 1 day
        let artworkLifespan: TimeInterval = playcut.rotation ? .thirtyDays : .oneDay

        let timer = Core.Timer.start()

        for fetcher in self.fetchers {
            do {
                let artwork = try await fetcher.fetchArtwork(for: playcut)
                // NSFW classification is now handled server-side by the backend proxy.
                // The proxy returns 404 for NSFW artwork, which DiscogsArtworkService
                // translates to ServiceError.noResults.
                await self.cacheCoordinator.set(artwork: artwork, for: cacheKey, lifespan: artworkLifespan)
                return artwork
            } catch {
                Log(.info, category: .artwork, "No artwork found for \(cacheKey) using fetcher \(fetcher): \(error)")
            }
        }

        Log(.error, category: .artwork, "No artwork found for \(cacheKey) using any fetcher after \(timer.duration()) seconds")
        await self.cacheCoordinator.set(value: Error.noArtworkAvailable, for: errorCacheKey, lifespan: .thirtyDays)

        return nil
    }

    private func removeTask(for id: String) {
        inflightTasks[id] = nil
    }

    /// Releases in-flight tasks to reduce memory pressure.
    /// Called in response to `UIApplication.didReceiveMemoryWarningNotification`.
    public func releaseMemory() {
        let count = inflightTasks.count
        for task in inflightTasks.values {
            task.cancel()
        }
        inflightTasks.removeAll()
        if count > 0 {
            Log(.info, category: .artwork, "Released \(count) in-flight artwork tasks due to memory warning")
        }
    }
}
