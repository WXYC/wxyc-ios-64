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
                guard try await NSFWDetector().checkNSFW(cgImage: artwork) == .sfw else {
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
