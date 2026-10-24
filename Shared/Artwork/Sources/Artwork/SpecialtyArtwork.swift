//
//  SpecialtyArtwork.swift
//  Artwork
//
//  The specialty program's logo: which URL to load, when to fall back to the
//  text tile, and the URL-keyed entry point into the shared artwork cache.
//
//  Created by Jake Bromberg on 10/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Caching
import CoreGraphics
import Core
import ImageIO
import Logger
import Playlist

/// The pure decisions behind `SpecialtyArtworkView`, kept free of SwiftUI and the network so a table can test them.
public enum SpecialtyArtwork {
    /// The logo to load for `program`, or `nil` when it has none and the tile is all there is.
    public static func logoURL(for program: SpecialtyShowRef) -> URL? {
        program.artwork?.squareURL
    }

    /// The program's logo through the shared artwork cache, or `nil` when it has none or the load fails,
    /// so a caller that cannot show a broken image draws the text tile instead. A program with no logo URL
    /// gets its ``bundledLogo(for:)``, if it has one (DEBUG builds only).
    public static func logo(for program: SpecialtyShowRef) async -> CGImage? {
        await logo(for: program, cache: .AlbumArt, session: URLSession.shared)
    }

    /// How long a downloaded logo stays cached.
    static let lifespan: TimeInterval = .thirtyDays

    /// ``logo(for:)`` decoded no larger than `maxPixelSize` on its longest side. For a surface with a tight
    /// memory limit, such as the widget extension, which must never decode a full-size logo. Shares the cached
    /// bytes, and the bundled fallback, with ``logo(for:)``.
    public static func logo(for program: SpecialtyShowRef, maxPixelSize: Int) async -> CGImage? {
        await logo(for: program, maxPixelSize: maxPixelSize, cache: .AlbumArt, session: URLSession.shared)
    }

    /// The one implementation behind both public entry points, with the cache and the network session injected
    /// so a test can count downloads.
    static func logo(
        for program: SpecialtyShowRef,
        maxPixelSize: Int = Int(ArtworkCacheConfiguration.targetWidth),
        cache: CacheCoordinator,
        session: any WebSession
    ) async -> CGImage? {
        guard let url = logoURL(for: program) else { return bundledLogo(for: program, maxPixelSize: maxPixelSize) }
        return try? await cache.image(from: url, maxPixelSize: maxPixelSize, session: session)
    }

    /// Decodes `data` no larger than `maxPixelSize` (by default the artwork cache's target width) on its longest
    /// side, keeping the aspect ratio and applying the image's orientation. Smaller images keep their size. The
    /// decode itself is downsampled, so a 1024-pixel logo is never held at full size. `data` is not modified,
    /// trimmed or re-encoded.
    static func decodeLogo(from data: Data, maxPixelSize: Int = Int(ArtworkCacheConfiguration.targetWidth)) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

extension CacheCoordinator {
    /// Returns the image at `url`, from this cache when present, otherwise downloaded with `session` and stored.
    ///
    /// The URL string is the cache key, so the same logo is never fetched twice while it is cached. The
    /// downloaded bytes are stored as-is, with none of the album-art processing (white-border trimming,
    /// re-encoding) that `set(artwork:for:lifespan:)` applies, and both paths decode them with the same downsample
    /// to `maxPixelSize` (`SpecialtyArtwork.decodeLogo(from:maxPixelSize:)`), so a logo looks the same on its first
    /// appearance and on every cache hit. Failures throw and are never cached, so a transient error does not pin
    /// the tile. Cancellation is rethrown without being logged as a failure.
    func image(from url: URL, maxPixelSize: Int = Int(ArtworkCacheConfiguration.targetWidth), session: any WebSession = URLSession.shared) async throws -> CGImage {
        let key = url.absoluteString
        if let cached = try? data(for: key), let image = SpecialtyArtwork.decodeLogo(from: cached, maxPixelSize: maxPixelSize) {
            return image
        }
        do {
            let downloaded = try await session.data(from: url)
            guard let image = SpecialtyArtwork.decodeLogo(from: downloaded, maxPixelSize: maxPixelSize) else {
                throw ServiceError.noResults
            }
            await setData(downloaded, for: key, lifespan: SpecialtyArtwork.lifespan)
            return image
        } catch {
            if !isCancellation(error) {
                Log(.warning, category: .artwork, "Specialty logo fetch failed for \(key): \(error)")
            }
            throw error
        }
    }
}
