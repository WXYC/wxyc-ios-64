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

    private var fetchers: [any ArtworkService]
    private let cacheCoordinator: CacheCoordinator
    private let errorCache: CacheCoordinator
    private var inflightTasks: [String: Task<CGImage?, Never>] = [:]

    /// Creates the artwork service with the default fetcher chain (cache + URL fetcher).
    ///
    /// Additional fetchers (e.g. the Discogs fallback once backend secrets land) are
    /// added at runtime via ``addFetcher(_:)``. This service is intended to be a
    /// stable identity for the lifetime of the app.
    public init() {
        self.init(
            fetchers: [
                CacheCoordinator.AlbumArt,
                URLArtworkFetcher(),
            ],
            cacheCoordinator: .AlbumArt
        )
    }

    /// Creates the artwork service with a custom fetcher chain.
    public init(
        fetchers: [any ArtworkService],
        cacheCoordinator: CacheCoordinator,
        errorCache: CacheCoordinator = .ArtworkErrors
    ) {
        self.fetchers = fetchers
        self.cacheCoordinator = cacheCoordinator
        self.errorCache = errorCache
    }

    /// Appends a fetcher to the chain and clears the negative cache.
    ///
    /// The negative-cache clear is part of the contract: previously-failed lookups
    /// must be retried against the augmented chain, otherwise the new fetcher would
    /// be silently bypassed by 30-day "no artwork available" entries.
    public func addFetcher(_ fetcher: any ArtworkService) async {
        fetchers.append(fetcher)
        await errorCache.clearAll()
        Log(.info, category: .artwork, "Added fetcher \(fetcher) and cleared negative cache")
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

        // Check positive cache first. Artwork may have been stored by an external
        // code path (e.g. metadata fallback in detail view) after a negative cache
        // entry was recorded.
        if let cached = try? await cacheCoordinator.fetchArtwork(for: playcut) {
            return cached
        }

        if let cachedError: Error = try? await self.errorCache.fetchError(for: cacheKey),
           Error.allCases.contains(cachedError) {
            Log(.info, category: .artwork, "Cached error for \(cacheKey): \(cachedError)")
            return nil
        }

        // Rotation plays get cached for 30 days; non-rotation plays for 1 day
        let artworkLifespan: TimeInterval = playcut.rotation ? .thirtyDays : .oneDay

        let timer = Core.Timer.start()
        var hadTransientError = false

        for fetcher in self.fetchers {
            do {
                let artwork = try await fetcher.fetchArtwork(for: playcut)
                await self.cacheCoordinator.set(artwork: artwork, for: cacheKey, lifespan: artworkLifespan)
                return artwork
            } catch let error as URLError where Self.isTransient(error) {
                // Server-side or networking blip — retry next time, don't poison the cache.
                Log(.warning, category: .artwork, "Transient error for \(cacheKey) using fetcher \(fetcher): \(error)")
                hadTransientError = true
            } catch {
                Log(.info, category: .artwork, "No artwork found for \(cacheKey) using fetcher \(fetcher): \(error)")
            }
        }

        Log(.error, category: .artwork, "No artwork found for \(cacheKey) using any fetcher after \(timer.duration()) seconds")

        // Only cache definitive "not found" outcomes. Transient errors must retry —
        // notably URLError.cancelled, which fires when a row's `.task` is torn down
        // mid-flight on launch and would otherwise persist as a 30-day "no artwork"
        // verdict for an album we never actually finished asking about.
        if !hadTransientError {
            await self.errorCache.set(value: Error.noArtworkAvailable, for: cacheKey, lifespan: .thirtyDays)
        }

        return nil
    }

    /// URLError codes that represent transient conditions which should NOT be cached
    /// as a definitive "no artwork available" verdict.
    private static func isTransient(_ error: URLError) -> Bool {
        switch error.code {
        case .badServerResponse,
             .timedOut,
             .cancelled,
             .networkConnectionLost,
             .notConnectedToInternet,
             .dnsLookupFailed,
             .cannotConnectToHost,
             .cannotFindHost,
             .resourceUnavailable,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed,
             .secureConnectionFailed:
            true
        default:
            false
        }
    }

    private func removeTask(for id: String) {
        inflightTasks[id] = nil
    }

    /// Stores artwork fetched by an external code path (e.g. the metadata fallback
    /// in the detail view) and clears any negative cache entry for the same key.
    ///
    /// Call this when artwork is loaded outside the normal fetcher chain so that
    /// subsequent `fetchArtwork(for:)` calls find it in the positive cache.
    public func cacheExternalArtwork(_ image: CGImage, for playcut: Playcut) async {
        let cacheKey = playcut.artworkCacheKey
        let lifespan: TimeInterval = playcut.rotation ? .thirtyDays : .oneDay
        await cacheCoordinator.set(artwork: image, for: cacheKey, lifespan: lifespan)
        await errorCache.setData(nil, for: cacheKey, lifespan: 0)
    }

    /// Clears cached "no artwork available" errors so entries are retried with the current fetcher chain.
    /// Call this after upgrading the fetcher chain (e.g. adding the Discogs fallback).
    public func clearNegativeCache() async {
        await errorCache.clearAll()
        Log(.info, category: .artwork, "Cleared artwork negative cache")
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
