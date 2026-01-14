//
//  ColorPaletteServiceTests.swift
//  ColorPalette
//
//  Tests for ColorPaletteService extraction and caching behavior.
//
//  Created by Jake Bromberg on 12/28/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Testing
@testable import ColorPalette
@testable import Caching
@testable import Core

#if canImport(UIKit)
import UIKit

@Suite("ColorPaletteService Tests")
struct ColorPaletteServiceTests {

    // MARK: - Basic Generation Tests

    @Test("Generates palette from solid color image")
    func generatesPaletteFromSolidColorImage() async throws {
        let service = ColorPaletteService(cacheCoordinator: .AlbumArt)
        let image = createSolidColorImage(.red)

        let palette = try await service.palette(
            for: image,
            cacheKey: "test-red",
            mode: .triad
        )

        #expect(palette.colors.count == 3)
        #expect(palette.mode == .triad)
        // Dominant color should be reddish (around 0 degrees)
        #expect(palette.dominantColor.hue < 20 || palette.dominantColor.hue > 340)
    }

    @Test("Generates different palettes for different modes")
    func generatesDifferentPalettesForDifferentModes() async throws {
        let service = ColorPaletteService(cacheCoordinator: .AlbumArt)
        let image = createSolidColorImage(.blue)

        let triad = try await service.palette(for: image, cacheKey: "test-blue-1", mode: .triad)
        let complementary = try await service.palette(for: image, cacheKey: "test-blue-2", mode: .complementary)
        let square = try await service.palette(for: image, cacheKey: "test-blue-3", mode: .square)

        #expect(triad.colors.count == 3)
        #expect(complementary.colors.count == 2)
        #expect(square.colors.count == 4)
    }

    // MARK: - All Palettes Tests

    @Test("Generates all palettes at once")
    func generatesAllPalettes() async throws {
        let service = ColorPaletteService(cacheCoordinator: .AlbumArt)
        let image = createSolidColorImage(.green)

        let allPalettes = try await service.allPalettes(
            for: image,
            cacheKey: "test-all-palettes"
        )

        #expect(allPalettes.count == PaletteMode.allCases.count)

        for mode in PaletteMode.allCases {
            #expect(allPalettes[mode] != nil)
            #expect(allPalettes[mode]?.mode == mode)
            #expect(allPalettes[mode]?.colors.count == mode.colorCount)
        }
    }

    @Test("All palettes share same dominant color")
    func allPalettesShareSameDominantColor() async throws {
        let service = ColorPaletteService(cacheCoordinator: .AlbumArt)
        let image = createSolidColorImage(.purple)

        let allPalettes = try await service.allPalettes(
            for: image,
            cacheKey: "test-shared-dominant"
        )

        let dominantColors = allPalettes.values.map(\.dominantColor)
        let firstDominant = dominantColors.first

        // All palettes should have the same dominant color
        for dominant in dominantColors {
            #expect(dominant == firstDominant)
        }
    }

    // MARK: - Caching Tests

    @Test("Returns cached palette on subsequent calls")
    func returnsCachedPalette() async throws {
        let service = ColorPaletteService(cacheCoordinator: .AlbumArt)
        let image = createSolidColorImage(.orange)
        let cacheKey = "test-cached-\(UUID().uuidString)"

        // First call
        let palette1 = try await service.palette(
            for: image,
            cacheKey: cacheKey,
            mode: .complementary
        )

        // Second call should return cached
        let palette2 = try await service.palette(
            for: image,
            cacheKey: cacheKey,
            mode: .complementary
        )

        #expect(palette1 == palette2)
    }

    @Test("Different modes have different cache keys")
    func differentModesHaveDifferentCacheKeys() async throws {
        let service = ColorPaletteService(cacheCoordinator: .AlbumArt)
        let image = createSolidColorImage(.cyan)
        let cacheKey = "test-modes-\(UUID().uuidString)"

        let triad = try await service.palette(for: image, cacheKey: cacheKey, mode: .triad)
        let square = try await service.palette(for: image, cacheKey: cacheKey, mode: .square)

        // Should be different palettes
        #expect(triad.colors.count != square.colors.count)
        #expect(triad.mode != square.mode)
    }

    // MARK: - Concurrent Request Tests

    @Test("Deduplicates concurrent requests for same palette")
    func deduplicatesConcurrentRequests() async throws {
        let service = ColorPaletteService(cacheCoordinator: .AlbumArt)
        let image = createSolidColorImage(.yellow)
        let cacheKey = "test-concurrent-\(UUID().uuidString)"

        async let palette1 = service.palette(for: image, cacheKey: cacheKey, mode: .triad)
        async let palette2 = service.palette(for: image, cacheKey: cacheKey, mode: .triad)
        async let palette3 = service.palette(for: image, cacheKey: cacheKey, mode: .triad)

        let results = try await [palette1, palette2, palette3]

        // All should be equal
        #expect(results.allSatisfy { $0 == results[0] })
    }

    @Test("Handles multiple different concurrent requests")
    func handlesMultipleDifferentConcurrentRequests() async throws {
        let service = ColorPaletteService(cacheCoordinator: .AlbumArt)
        let image = createSolidColorImage(.magenta)
        let baseKey = "test-multi-\(UUID().uuidString)"

        async let triad = service.palette(for: image, cacheKey: "\(baseKey)-1", mode: .triad)
        async let complementary = service.palette(for: image, cacheKey: "\(baseKey)-2", mode: .complementary)
        async let square = service.palette(for: image, cacheKey: "\(baseKey)-3", mode: .square)
        async let analogous = service.palette(for: image, cacheKey: "\(baseKey)-4", mode: .analogous)

        let results = try await [triad, complementary, square, analogous]

        #expect(results[0].mode == .triad)
        #expect(results[1].mode == .complementary)
        #expect(results[2].mode == .square)
        #expect(results[3].mode == .analogous)
    }

    // MARK: - Error Handling Tests

    @Test("Throws extraction error for nil CGImage")
    func throwsExtractionErrorForNilCGImage() async {
        let service = ColorPaletteService(cacheCoordinator: .AlbumArt)

        // Create an empty UIImage (no CGImage backing)
        let emptyImage = UIImage()

        await #expect(throws: ColorPaletteService.Error.extractionFailed) {
            try await service.palette(
                for: emptyImage,
                cacheKey: "test-empty",
                mode: .triad
            )
        }
    }

    // MARK: - Integration Tests

    @Test("Works with realistic album artwork dimensions")
    func worksWithRealisticAlbumArtworkDimensions() async throws {
        let service = ColorPaletteService(cacheCoordinator: .AlbumArt)

        // Typical album artwork size
        let size = CGSize(width: 600, height: 600)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            // Create a gradient-like image
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 300))
            UIColor.purple.setFill()
            context.fill(CGRect(x: 0, y: 300, width: 600, height: 300))
        }

        let palette = try await service.palette(
            for: image,
            cacheKey: "test-album-size",
            mode: .analogous
        )

        #expect(palette.colors.count == 5)
    }

    @Test("Handles non-square images")
    func handlesNonSquareImages() async throws {
        let service = ColorPaletteService(cacheCoordinator: .AlbumArt)

        let size = CGSize(width: 800, height: 400)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }

        let palette = try await service.palette(
            for: image,
            cacheKey: "test-non-square",
            mode: .square
        )

        #expect(palette.colors.count == 4)
        // Orange is around 30-40 degrees
        #expect(palette.dominantColor.hue > 15 && palette.dominantColor.hue < 55)
    }

    // MARK: - Test Helpers

    private func createSolidColorImage(_ color: UIColor) -> Image {
        let size = CGSize(width: 100, height: 100)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
#endif
