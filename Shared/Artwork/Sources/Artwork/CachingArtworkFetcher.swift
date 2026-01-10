//
//  CachingArtworkService.swift
//  Core
//
//  Created by Jake Bromberg on 3/1/25.
//

import Foundation
import Caching
import Core
import Logger
import Playlist

// TODO: Remove this and replace with `CachingArtworkService`.
extension CacheCoordinator: ArtworkService {
    // This is necessary because calling `value(for:)` on CacheCoordinator was somehow dispatching to
    // the `fetchArtwork(...)` method below.
    func fetchError(for cacheKeyId: String) async throws -> MultisourceArtworkService.Error {
        try await self.value(for: cacheKeyId)
    }
    
    public func fetchArtwork(for playcut: Playcut) async throws -> Image {
        let cachedData: Data = try self.data(for: playcut.artworkCacheKey)
        guard let artwork = Image(compatibilityData: cachedData) else {
            throw Error.noCachedResult
        }
        
        return artwork
    }
        
    func set(artwork: Image, for id: String, lifespan: TimeInterval) async {
        let scaledArtwork = artwork.scaledToWidth(ArtworkCacheConfiguration.targetWidth)
        let artworkData = scaledArtwork.heifData(
            compressionQuality: ArtworkCacheConfiguration.heifCompressionQuality
        ) ?? scaledArtwork.pngDataCompatibility
        self.setData(artworkData, for: id, lifespan: lifespan)
    }
}

// MARK: - PNG to HEIF Migration (DEBUG only)

#if DEBUG
/// PNG file signature (magic bytes): 0x89 P N G
private let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47]

extension CacheCoordinator {
    /// Migrates existing PNG artwork cache entries to HEIF format.
    ///
    /// This iterates over all entries in the AlbumArt cache, identifies PNG images
    /// by their magic bytes, scales them to the configured target width, and
    /// re-encodes them as HEIF for reduced cache size.
    ///
    /// - Note: DEBUG builds only. Safe to call multiple times; already-converted
    ///   entries (HEIF) are skipped.
    public static func migratePngCacheToHeif() async {
        let cache = CacheCoordinator.AlbumArt
        await cache.waitForPurge()

        var convertedCount = 0
        var skippedCount = 0
        var totalBytesSaved: Int = 0

        let allEntries = await cache.allEntries()

        for (key, metadata) in allEntries {
            guard let data = await cache.rawData(for: key) else {
                continue
            }

            // Check if this is a PNG by examining magic bytes
            guard isPng(data: data) else {
                skippedCount += 1
                continue
            }

            // Decode the PNG
            guard let image = Image(compatibilityData: data) else {
                Log(.warning, "Failed to decode PNG for key: \(key)")
                continue
            }

            // Scale and convert to HEIF
            let scaledImage = image.scaledToWidth(ArtworkCacheConfiguration.targetWidth)
            guard let heifData = scaledImage.heifData(
                compressionQuality: ArtworkCacheConfiguration.heifCompressionQuality
            ) else {
                Log(.warning, "Failed to encode HEIF for key: \(key)")
                continue
            }

            // Calculate savings
            let bytesSaved = data.count - heifData.count
            totalBytesSaved += bytesSaved

            // Write back with original metadata (preserving lifespan/expiry)
            await cache.setDataPreservingMetadata(heifData, metadata: metadata, for: key)
            convertedCount += 1

            Log(.info, "Converted \(key): \(data.count) → \(heifData.count) bytes (saved \(bytesSaved))")
        }

        let savedKB = Double(totalBytesSaved) / 1024.0
        Log(.info, "PNG→HEIF migration complete: \(convertedCount) converted, \(skippedCount) skipped, \(String(format: "%.1f", savedKB)) KB saved")
    }
}

private func isPng(data: Data) -> Bool {
    guard data.count >= pngSignature.count else { return false }
    return data.prefix(pngSignature.count).elementsEqual(pngSignature)
}
#endif
