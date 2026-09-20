//
//  MultisourceArtworkService.swift
//  Artwork
//
//  Aggregates artwork sources — the on-disk cache and the URL fetcher — trying
//  each in order until artwork is found. The backend's `artwork_url` is the only
//  network source: the app deliberately runs no speculative client-side search
//  (the removed Discogs free-text fallback once bound a wrong cover for 30 days).
//
//  Created by Jake Bromberg on 04/12/23.
//  Copyright © 2023 WXYC. All rights reserved.
//

import Foundation
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
#elseif canImport(AppKit)
import AppKit
#endif

public extension CGImage {
    /// Converts the CGImage to the platform `Image` type (`UIImage` on UIKit,
    /// `NSImage` on AppKit), sized to the CGImage's pixel dimensions.
    /// Safe to call from any thread.
    func toImage() -> Core.Image {
        #if canImport(UIKit)
        UIImage(cgImage: self)
        #elseif canImport(AppKit)
        NSImage(cgImage: self, size: NSSize(width: width, height: height))
        #endif
    }
}

// TODO: Rename to CompositeArtworkService and conform it to `ArtworkService`
public final actor MultisourceArtworkService: ArtworkService {
    enum Error: Swift.Error, Codable, CaseIterable {
        case noArtworkAvailable
        // Nothing writes this any more — the on-device NSFW filter is gone — but
        // this enum is the `Codable` payload persisted in `.ArtworkErrors` with a
        // 30-day lifespan, so the case stays until any entry that names it has
        // aged out. Dropping it makes those entries fail to decode.
        case nsfw
    }

    private let fetchers: [any ArtworkService]
    private let cacheCoordinator: CacheCoordinator
    private let errorCache: CacheCoordinator
    private var inflightTasks: [String: Task<CGImage?, Never>] = [:]

    /// Creates the artwork service with the fetcher chain (cache + URL fetcher).
    /// This service is intended to be a stable identity for the lifetime of the app.
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
        var hadConclusiveNegative = false

        for fetcher in self.fetchers {
            do {
                let artwork = try await fetcher.fetchArtwork(for: playcut)
                await self.cacheCoordinator.set(artwork: artwork, for: cacheKey, lifespan: artworkLifespan)
                return artwork
            } catch let error where Self.isTransient(error) {
                // Server-side or networking blip — retry next time, don't poison the cache.
                Log(.warning, category: .artwork, "Transient error for \(cacheKey) using fetcher \(fetcher): \(error)")
                hadTransientError = true
            } catch ServiceError.notAttempted {
                // Fetcher had no input to act on (e.g. no artwork URL yet because backend
                // enrichment hasn't completed). Not a verdict about whether artwork exists —
                // must not contribute to the negative cache, or a later poll carrying a
                // real URL would stay shadowed for 30 days.
                Log(.info, category: .artwork, "Fetcher \(fetcher) made no attempt for \(cacheKey)")
            } catch ServiceError.noResults {
                // The fetcher genuinely looked and found nothing. This is the only
                // outcome that justifies caching a definitive "no artwork available".
                Log(.info, category: .artwork, "No artwork found for \(cacheKey) using fetcher \(fetcher)")
                hadConclusiveNegative = true
            } catch {
                // Unknown / inconclusive (e.g. cache-miss `noCachedResult`). Treat
                // conservatively as a non-verdict so a single odd error doesn't
                // poison the cache against a track that may have art.
                Log(.info, category: .artwork, "Inconclusive failure for \(cacheKey) using fetcher \(fetcher): \(error)")
            }
        }

        // Distinguish "we tried real sources and they all came up empty" (worth
        // surfacing) from "no fetcher ever made a real attempt" (the common
        // not-yet-enriched case; per-playcut per-poll, would flood error logs).
        if hadConclusiveNegative {
            Log(.error, category: .artwork, "No artwork found for \(cacheKey) using any fetcher after \(timer.duration()) seconds")
        } else {
            Log(.info, category: .artwork, "Chain exhausted without conclusive verdict for \(cacheKey) after \(timer.duration()) seconds")
        }

        // Cache "no artwork available" only when at least one fetcher returned a
        // conclusive verdict and no transient errors occurred. Skip when:
        //   - any fetcher hit a transient error (might be art, network blipped) —
        //     notably URLError.cancelled, which fires when a row's `.task` is torn
        //     down mid-flight on launch and would otherwise persist as a 30-day
        //     "no artwork" verdict for an album we never finished asking about;
        //   - no fetcher actually returned a conclusive negative — the no-URL-yet
        //     path, where the chain abstained because backend enrichment hadn't
        //     resolved a URL. Caching here would shadow a real URL on the next poll.
        if hadConclusiveNegative && !hadTransientError {
            await self.errorCache.set(value: Error.noArtworkAvailable, for: cacheKey, lifespan: .thirtyDays)
        }

        return nil
    }

    /// Errors that represent transient conditions which should NOT be cached
    /// as a definitive "no artwork available" verdict. The single home for
    /// transient-vs-conclusive classification — new error types belong here,
    /// not in extra catch arms.
    private static func isTransient(_ error: any Swift.Error) -> Bool {
        // A non-2xx response from `WebSession.data(from:)` — the same
        // condition that used to surface as `URLError(.badServerResponse)`
        // (unconditionally transient below) before
        // `HTTPURLResponse.validateSuccessStatus()` started carrying the
        // real status code. Treated the same way: retry next time, don't
        // poison the negative cache.
        if error is HTTPStatusError { return true }
        guard let urlError = error as? URLError else { return false }
        return switch urlError.code {
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
