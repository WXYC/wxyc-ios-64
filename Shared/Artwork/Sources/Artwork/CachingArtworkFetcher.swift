//
//  CachingArtworkFetcher.swift
//  Artwork
//
//  Extends CacheCoordinator with ArtworkService conformance for cached artwork retrieval.
//  Handles HEIF/PNG encoding and image scaling for efficient storage.
//
//  Created by Jake Bromberg on 03/01/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
import Caching
import Core
import Logger
import Playlist
import ImageIO
import UniformTypeIdentifiers

// TODO: Remove this and replace with `CachingArtworkService`.
extension CacheCoordinator: ArtworkService {
    // This is necessary because calling `value(for:)` on CacheCoordinator was somehow dispatching to
    // the `fetchArtwork(...)` method below.
    func fetchError(for cacheKeyId: String) async throws -> MultisourceArtworkService.Error {
        try await self.value(for: cacheKeyId)
    }

    public func fetchArtwork(for playcut: Playcut) async throws -> CGImage {
        let cachedData: Data = try self.data(for: playcut.artworkCacheKey)
        guard let cgImage = createCGImage(from: cachedData) else {
            throw Error.noCachedResult
        }

        return cgImage
    }

    func set(artwork: CGImage, for id: String, lifespan: TimeInterval) async {
        let scaledArtwork = scaleCGImage(artwork, toWidth: ArtworkCacheConfiguration.targetWidth)
        let artworkData = encodeCGImageAsHEIF(scaledArtwork, compressionQuality: ArtworkCacheConfiguration.heifCompressionQuality)
            ?? encodeCGImageAsPNG(scaledArtwork)
        self.setData(artworkData, for: id, lifespan: lifespan)
    }
}

// MARK: - CGImage Scaling and Encoding

private func scaleCGImage(_ image: CGImage, toWidth targetWidth: CGFloat) -> CGImage {
    let currentWidth = CGFloat(image.width)
    guard currentWidth > targetWidth else { return image }

    let scale = targetWidth / currentWidth
    let targetHeight = CGFloat(image.height) * scale
    let targetSize = CGSize(width: targetWidth, height: targetHeight)

    let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: Int(targetSize.width),
        height: Int(targetSize.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return image
    }

    context.interpolationQuality = .high
    context.draw(image, in: CGRect(origin: .zero, size: targetSize))

    return context.makeImage() ?? image
}

private func encodeCGImageAsHEIF(_ image: CGImage, compressionQuality: CGFloat) -> Data? {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data as CFMutableData,
        UTType.heic.identifier as CFString,
        1,
        nil
    ) else {
        return nil
    }

    CGImageDestinationAddImage(destination, image, [
        kCGImageDestinationLossyCompressionQuality: compressionQuality
    ] as CFDictionary)

    guard CGImageDestinationFinalize(destination) else { return nil }
    return data as Data
}

private func encodeCGImageAsPNG(_ image: CGImage) -> Data? {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data as CFMutableData,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        return nil
    }

    CGImageDestinationAddImage(destination, image, nil)

    guard CGImageDestinationFinalize(destination) else { return nil }
    return data as Data
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
                Log(.warning, category: .artwork, "Failed to decode PNG for key: \(key)")
                continue
            }

            // Scale and convert to HEIF
            let scaledImage = image.scaledToWidth(ArtworkCacheConfiguration.targetWidth)
            guard let heifData = scaledImage.heifData(
                compressionQuality: ArtworkCacheConfiguration.heifCompressionQuality
            ) else {
                Log(.warning, category: .artwork, "Failed to encode HEIF for key: \(key)")
                continue
            }

            // Calculate savings
            let bytesSaved = data.count - heifData.count
            totalBytesSaved += bytesSaved

            // Write back with original metadata (preserving lifespan/expiry)
            await cache.setDataPreservingMetadata(heifData, metadata: metadata, for: key)
            convertedCount += 1

            Log(.info, category: .artwork, "Converted \(key): \(data.count) → \(heifData.count) bytes (saved \(bytesSaved))")
        }

        let savedKB = Double(totalBytesSaved) / 1024.0
        Log(.info, category: .artwork, "PNG→HEIF migration complete: \(convertedCount) converted, \(skippedCount) skipped, \(String(format: "%.1f", savedKB)) KB saved")
    }
}

private func isPng(data: Data) -> Bool {
    guard data.count >= pngSignature.count else { return false }
    return data.prefix(pngSignature.count).elementsEqual(pngSignature)
}
#endif
