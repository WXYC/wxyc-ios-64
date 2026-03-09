//
//  WhiteBorderTrimmerTests.swift
//  ArtworkTests
//
//  Tests for white border detection and trimming of album artwork images.
//
//  Created by Jake Bromberg on 03/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import CoreGraphics
import Foundation
@testable import Artwork

@Suite("White Border Trimmer Tests")
struct WhiteBorderTrimmerTests {

    @Test("No border - solid color image is unchanged")
    func noBorder() {
        let image = createBorderedImage(
            size: CGSize(width: 100, height: 100),
            borderColor: .blue,
            contentColor: .blue,
            top: 0, bottom: 0, left: 0, right: 0
        )

        let result = trimWhiteBorder(from: image)

        #expect(result.width == 100)
        #expect(result.height == 100)
    }

    @Test("Uniform 5px white border is trimmed")
    func uniformWhiteBorder() {
        let image = createBorderedImage(
            size: CGSize(width: 110, height: 110),
            borderColor: .white,
            contentColor: .blue,
            top: 5, bottom: 5, left: 5, right: 5
        )

        let result = trimWhiteBorder(from: image)

        #expect(result.width == 100)
        #expect(result.height == 100)
    }

    @Test("Top border only is trimmed")
    func topBorderOnly() {
        let image = createBorderedImage(
            size: CGSize(width: 100, height: 104),
            borderColor: .white,
            contentColor: .blue,
            top: 4, bottom: 0, left: 0, right: 0
        )

        let result = trimWhiteBorder(from: image)

        #expect(result.width == 100)
        #expect(result.height == 100)
    }

    @Test("Left and right borders only are trimmed")
    func leftRightBordersOnly() {
        let image = createBorderedImage(
            size: CGSize(width: 106, height: 100),
            borderColor: .white,
            contentColor: .blue,
            top: 0, bottom: 0, left: 3, right: 3
        )

        let result = trimWhiteBorder(from: image)

        #expect(result.width == 100)
        #expect(result.height == 100)
    }

    @Test("Near-white JPEG artifact border is trimmed")
    func nearWhiteJPEGArtifacts() {
        let nearWhite = TestColor(r: 245, g: 248, b: 242, a: 255)
        let image = createBorderedImage(
            size: CGSize(width: 110, height: 110),
            borderColor: nearWhite,
            contentColor: .blue,
            top: 5, bottom: 5, left: 5, right: 5
        )

        let result = trimWhiteBorder(from: image)

        #expect(result.width == 100)
        #expect(result.height == 100)
    }

    @Test("Light gray border below threshold is not trimmed")
    func lightGrayBorderNotTrimmed() {
        let lightGray = TestColor(r: 200, g: 200, b: 200, a: 255)
        let image = createBorderedImage(
            size: CGSize(width: 110, height: 110),
            borderColor: lightGray,
            contentColor: .blue,
            top: 5, bottom: 5, left: 5, right: 5
        )

        let result = trimWhiteBorder(from: image)

        #expect(result.width == 110)
        #expect(result.height == 110)
    }

    @Test("Trim capped at 5% of dimension")
    func capAt5Percent() {
        // 200x200 image with 15px white border (7.5% of dimension)
        // Should cap trim at 10px per side (5%)
        let image = createBorderedImage(
            size: CGSize(width: 200, height: 200),
            borderColor: .white,
            contentColor: .blue,
            top: 15, bottom: 15, left: 15, right: 15
        )

        let result = trimWhiteBorder(from: image)

        #expect(result.width == 180)
        #expect(result.height == 180)
    }

    @Test("Non-square image with border")
    func nonSquareImage() {
        let image = createBorderedImage(
            size: CGSize(width: 200, height: 100),
            borderColor: .white,
            contentColor: .blue,
            top: 3, bottom: 3, left: 3, right: 3
        )

        let result = trimWhiteBorder(from: image)

        #expect(result.width == 194)
        #expect(result.height == 94)
    }

    @Test("All-white image is unchanged (safety valve)")
    func allWhiteImageUnchanged() {
        let image = createBorderedImage(
            size: CGSize(width: 100, height: 100),
            borderColor: .white,
            contentColor: .white,
            top: 0, bottom: 0, left: 0, right: 0
        )

        let result = trimWhiteBorder(from: image)

        #expect(result.width == 100)
        #expect(result.height == 100)
    }

    @Test("Noisy border row at 95% threshold is trimmed")
    func noisyBorderAtThreshold() {
        // Create a 100x10 image where first row has 95 white + 5 blue pixels
        let image = createImageWithNoisyBorder(
            width: 100, height: 10,
            whitePixelsInBorderRow: 95,
            borderRows: 1
        )

        let result = trimWhiteBorder(from: image)

        // The first row should be trimmed (95% white meets the threshold)
        #expect(result.height == 9)
    }

    @Test("Noisy border row below 95% threshold is not trimmed")
    func noisyBorderBelowThreshold() {
        // Create a 100x10 image where first row has 90 white + 10 blue pixels
        let image = createImageWithNoisyBorder(
            width: 100, height: 10,
            whitePixelsInBorderRow: 90,
            borderRows: 1
        )

        let result = trimWhiteBorder(from: image)

        // The row should NOT be trimmed (90% white is below threshold)
        #expect(result.height == 10)
    }

    @Test("Transparent white border is not trimmed")
    func transparentWhiteBorderNotTrimmed() {
        let transparentWhite = TestColor(r: 255, g: 255, b: 255, a: 128)
        let image = createBorderedImage(
            size: CGSize(width: 110, height: 110),
            borderColor: transparentWhite,
            contentColor: .blue,
            top: 5, bottom: 5, left: 5, right: 5
        )

        let result = trimWhiteBorder(from: image)

        #expect(result.width == 110)
        #expect(result.height == 110)
    }
}

// MARK: - Test Helpers

struct TestColor {
    let r: UInt8
    let g: UInt8
    let b: UInt8
    let a: UInt8

    static let white = TestColor(r: 255, g: 255, b: 255, a: 255)
    static let blue = TestColor(r: 0, g: 0, b: 255, a: 255)
}

/// Creates a CGImage with a colored border around a colored content area.
///
/// The total image size is `size`. The border is drawn in `borderColor` with the specified
/// thicknesses, and the remaining interior is filled with `contentColor`.
func createBorderedImage(
    size: CGSize,
    borderColor: TestColor,
    contentColor: TestColor,
    top: Int,
    bottom: Int,
    left: Int,
    right: Int
) -> CGImage {
    let width = Int(size.width)
    let height = Int(size.height)
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

    for y in 0..<height {
        for x in 0..<width {
            let offset = (y * width + x) * bytesPerPixel
            let isBorder = y < top || y >= height - bottom || x < left || x >= width - right
            let color = isBorder ? borderColor : contentColor
            pixels[offset] = color.r
            pixels[offset + 1] = color.g
            pixels[offset + 2] = color.b
            pixels[offset + 3] = color.a
        }
    }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let data = Data(pixels)
    let provider = CGDataProvider(data: data as CFData)!

    return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )!
}

/// Creates an image with a "noisy" top border for threshold testing.
///
/// The first `borderRows` rows contain `whitePixelsInBorderRow` white pixels followed
/// by blue pixels. All remaining rows are solid blue.
func createImageWithNoisyBorder(
    width: Int,
    height: Int,
    whitePixelsInBorderRow: Int,
    borderRows: Int
) -> CGImage {
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

    for y in 0..<height {
        for x in 0..<width {
            let offset = (y * width + x) * bytesPerPixel
            let isWhite = y < borderRows && x < whitePixelsInBorderRow
            if isWhite {
                pixels[offset] = 255     // R
                pixels[offset + 1] = 255 // G
                pixels[offset + 2] = 255 // B
                pixels[offset + 3] = 255 // A
            } else {
                pixels[offset] = 0       // R
                pixels[offset + 1] = 0   // G
                pixels[offset + 2] = 255 // B
                pixels[offset + 3] = 255 // A
            }
        }
    }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let data = Data(pixels)
    let provider = CGDataProvider(data: data as CFData)!

    return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )!
}
