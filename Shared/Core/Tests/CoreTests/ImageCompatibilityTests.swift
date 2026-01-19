//
//  ImageCompatibilityTests.swift
//  Core
//
//  Tests for cross-platform image encoding utilities.
//
//  Created by Jake Bromberg on 01/09/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Core

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@Suite("Image Compatibility", .serialized)
struct ImageCompatibilityTests {
    // MARK: - HEIF Encoding Tests

    @Test("heifData returns valid data for valid image")
    func heifDataReturnsValidData() throws {
        let image = try createTestImage(width: 100, height: 100)
        let heifData = image.heifData()

        #expect(heifData != nil)
        #expect(heifData!.count > 0)
    }

    @Test("heifData respects compression quality parameter")
    func heifDataRespectsCompressionQuality() throws {
        let image = try createTestImage(width: 200, height: 200)

        let highQualityData = image.heifData(compressionQuality: 1.0)
        let lowQualityData = image.heifData(compressionQuality: 0.1)

        #expect(highQualityData != nil)
        #expect(lowQualityData != nil)
        // Higher quality should generally produce larger data
        #expect(highQualityData!.count >= lowQualityData!.count)
    }

    @Test("heifData produces valid image data that can be decoded")
    func heifDataProducesDecodableImage() throws {
        let originalImage = try createTestImage(width: 150, height: 150)
        let heifData = try #require(originalImage.heifData())

        let decodedImage = Image(compatibilityData: heifData)
        #expect(decodedImage != nil)
    }

    // MARK: - Scaling Tests

    @Test("scaledToWidth scales images wider than target")
    func scaledToWidthScalesLargeImages() throws {
        let image = try createTestImage(width: 1000, height: 500)
        let scaled = image.scaledToWidth(400)

        #expect(scaled.size.width == 400)
        #expect(scaled.size.height == 200) // Maintains 2:1 aspect ratio
    }

    @Test("scaledToWidth returns original for images at target width")
    func scaledToWidthReturnsOriginalAtTargetWidth() throws {
        let image = try createTestImage(width: 400, height: 300)
        let scaled = image.scaledToWidth(400)

        // Should return the same image (no scaling needed)
        #expect(scaled.size.width == 400)
        #expect(scaled.size.height == 300)
    }

    @Test("scaledToWidth returns original for images below target width")
    func scaledToWidthReturnsOriginalBelowTargetWidth() throws {
        let image = try createTestImage(width: 200, height: 150)
        let scaled = image.scaledToWidth(400)

        // Should return the same image (smaller than target)
        #expect(scaled.size.width == 200)
        #expect(scaled.size.height == 150)
    }

    @Test("scaledToWidth maintains aspect ratio")
    func scaledToWidthMaintainsAspectRatio() throws {
        let image = try createTestImage(width: 800, height: 600) // 4:3 aspect ratio
        let scaled = image.scaledToWidth(400)

        #expect(scaled.size.width == 400)
        #expect(scaled.size.height == 300) // 4:3 aspect ratio maintained
    }

    @Test("scaledToWidth handles square images")
    func scaledToWidthHandlesSquareImages() throws {
        let image = try createTestImage(width: 1000, height: 1000)
        let scaled = image.scaledToWidth(500)

        #expect(scaled.size.width == 500)
        #expect(scaled.size.height == 500)
    }

    @Test("scaledToWidth handles tall images")
    func scaledToWidthHandlesTallImages() throws {
        let image = try createTestImage(width: 400, height: 800) // 1:2 aspect ratio
        let scaled = image.scaledToWidth(200)

        #expect(scaled.size.width == 200)
        #expect(scaled.size.height == 400) // 1:2 aspect ratio maintained
    }

    // MARK: - Combined HEIF + Scaling Tests

    @Test("scaled HEIF is smaller than scaled PNG")
    func scaledHeifIsSmallerThanScaledPng() throws {
        let image = try createTestImage(width: 1000, height: 1000)
        let scaled = image.scaledToWidth(430)

        let heifData = scaled.heifData(compressionQuality: 0.8)
        let pngData = scaled.pngDataCompatibility

        #expect(heifData != nil)
        #expect(pngData != nil)
        // HEIF should be significantly smaller than PNG
        #expect(heifData!.count < pngData!.count)
    }

    // MARK: - Helpers

    private func createTestImage(width: Int, height: Int) throws -> Image {
        #if canImport(UIKit)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { context in
            // Create a gradient-like pattern for more realistic compression testing
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            UIColor.red.setFill()
            context.fill(CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2))
        }
        #elseif canImport(AppKit)
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSColor.red.setFill()
        NSRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2).fill()
        image.unlockFocus()
        return image
        #endif
    }
}
