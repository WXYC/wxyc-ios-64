//
//  ImageCompatability.swift
//  Core
//
//  Created by Jake Bromberg on 3/1/25.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
public typealias Image = UIImage

public extension Image {
    // Unified helper to get PNG data in cross‑platform code
    var pngDataCompatibility: Data? { self.pngData() }
    // Unified initializer used when reconstructing from Data
    convenience init?(compatibilityData data: Data) { self.init(data: data) }

    /// Encodes the image as HEIF data with the specified compression quality.
    /// - Parameter compressionQuality: Compression quality from 0.0 (most compression) to 1.0 (least compression). Defaults to 0.8.
    /// - Returns: HEIF-encoded data, or nil if encoding fails.
    func heifData(compressionQuality: CGFloat = 0.8) -> Data? {
        guard let cgImage = self.cgImage else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.heic.identifier as CFString,
            1,
            nil
        ) else { return nil }

        CGImageDestinationAddImage(destination, cgImage, [
            kCGImageDestinationLossyCompressionQuality: compressionQuality
        ] as CFDictionary)

        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// Scales the image to the specified width, maintaining aspect ratio.
    /// - Parameter targetWidth: The desired width in points.
    /// - Returns: A scaled image, or the original if already at or below target width.
    func scaledToWidth(_ targetWidth: CGFloat) -> Image {
        guard size.width > targetWidth else { return self }

        let scale = targetWidth / size.width
        let targetSize = CGSize(width: targetWidth, height: size.height * scale)

        #if os(watchOS)
        // UIGraphicsImageRenderer is unavailable on watchOS, use CoreGraphics
        guard let cgImage = self.cgImage else { return self }
        let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(targetSize.width),
            height: Int(targetSize.height),
            bitsPerComponent: cgImage.bitsPerComponent,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: cgImage.bitmapInfo.rawValue
        ) else { return self }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(origin: .zero, size: targetSize))

        guard let scaledCGImage = context.makeImage() else { return self }
        return UIImage(cgImage: scaledCGImage)
        #else
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        #endif
    }
}

#elseif canImport(AppKit)
import AppKit
public typealias Image = NSImage

public extension Image {
    // Convert NSImage to PNG data
    var pngDataCompatibility: Data? {
        guard
            let tiff = self.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let data = rep.representation(using: .png, properties: [:])
        else { return nil }
        return data
    }

    // NSImage already supports init?(data:)
    convenience init?(compatibilityData data: Data) {
        self.init(data: data)
    }

    /// Encodes the image as HEIF data with the specified compression quality.
    /// - Parameter compressionQuality: Compression quality from 0.0 (most compression) to 1.0 (least compression). Defaults to 0.8.
    /// - Returns: HEIF-encoded data, or nil if encoding fails.
    func heifData(compressionQuality: CGFloat = 0.8) -> Data? {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.heic.identifier as CFString,
            1,
            nil
        ) else { return nil }

        CGImageDestinationAddImage(destination, cgImage, [
            kCGImageDestinationLossyCompressionQuality: compressionQuality
        ] as CFDictionary)

        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// Scales the image to the specified width, maintaining aspect ratio.
    /// - Parameter targetWidth: The desired width in points.
    /// - Returns: A scaled image, or the original if already at or below target width.
    func scaledToWidth(_ targetWidth: CGFloat) -> Image {
        guard size.width > targetWidth else { return self }

        let scale = targetWidth / size.width
        let targetSize = NSSize(width: targetWidth, height: size.height * scale)

        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        self.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1.0
        )
        newImage.unlockFocus()
        return newImage
    }
}

#else
#error("Neither UIKit nor AppKit is available to define Image alias.")
#endif
