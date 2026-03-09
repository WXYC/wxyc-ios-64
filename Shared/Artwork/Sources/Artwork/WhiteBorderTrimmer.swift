//
//  WhiteBorderTrimmer.swift
//  Artwork
//
//  Detects and crops thin white borders from album artwork images.
//  Scans each edge inward, counting near-white pixels per scanline,
//  and trims lines where 95%+ of pixels are near-white, up to 5% of the dimension.
//
//  Created by Jake Bromberg on 03/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import CoreGraphics

// MARK: - Thresholds

/// Minimum value (inclusive) for each R, G, B, A channel to qualify as "near-white."
private let nearWhiteMin: UInt8 = 240

/// Fraction of pixels in a scanline that must be near-white to count as border.
private let scanlineConsensus: Double = 0.95

/// Maximum fraction of a dimension that can be trimmed per edge.
private let maxTrimFraction: Double = 0.05

/// Minimum fraction of each original dimension that must remain after trimming.
private let minRemainingFraction: Double = 0.50

// MARK: - Public API

/// Trims near-white borders from a CGImage.
///
/// Scans each edge (top, bottom, left, right) inward one scanline at a time.
/// A scanline is considered "border" if 95%+ of its pixels have all RGB channels
/// and alpha >= 240. Scanning stops at the first non-border scanline or when
/// 5% of that dimension has been reached. Returns the original image if no
/// trimming is needed or if trimming would reduce either dimension below 50%.
///
/// - Parameter image: The source image to trim.
/// - Returns: A cropped image with white borders removed, or the original if no trimming is needed.
func trimWhiteBorder(from image: CGImage) -> CGImage {
    let width = image.width
    let height = image.height

    guard width > 0, height > 0 else { return image }

    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return image
    }

    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    guard let data = context.data else { return image }

    let pixels = data.assumingMemoryBound(to: UInt8.self)

    // Safety valve: if the image is predominantly near-white, there's no
    // content border to reveal, so return unchanged.
    if isImageMostlyWhite(pixels: pixels, totalPixels: width * height) {
        return image
    }

    let maxTrimH = max(1, Int(Double(height) * maxTrimFraction))
    let maxTrimW = max(1, Int(Double(width) * maxTrimFraction))

    let topTrim = scanEdge(pixels: pixels, width: width, height: height, edge: .top, maxTrim: maxTrimH)
    let bottomTrim = scanEdge(pixels: pixels, width: width, height: height, edge: .bottom, maxTrim: maxTrimH)
    let leftTrim = scanEdge(pixels: pixels, width: width, height: height, edge: .left, maxTrim: maxTrimW)
    let rightTrim = scanEdge(pixels: pixels, width: width, height: height, edge: .right, maxTrim: maxTrimW)

    guard topTrim > 0 || bottomTrim > 0 || leftTrim > 0 || rightTrim > 0 else {
        return image
    }

    let newWidth = width - leftTrim - rightTrim
    let newHeight = height - topTrim - bottomTrim

    guard
        newWidth >= Int(Double(width) * minRemainingFraction),
        newHeight >= Int(Double(height) * minRemainingFraction)
    else {
        return image
    }

    // CGImage coordinate system: origin is top-left for cropping
    let cropRect = CGRect(x: leftTrim, y: topTrim, width: newWidth, height: newHeight)

    return image.cropping(to: cropRect) ?? image
}

// MARK: - Edge Scanning

private enum Edge {
    case top, bottom, left, right
}

/// Scans inward from the given edge, counting consecutive scanlines that are near-white.
///
/// - Parameters:
///   - pixels: Pointer to RGBA pixel data.
///   - width: Image width in pixels.
///   - height: Image height in pixels.
///   - edge: Which edge to scan from.
///   - maxTrim: Maximum number of scanlines to trim.
/// - Returns: Number of border scanlines detected.
private func scanEdge(
    pixels: UnsafePointer<UInt8>,
    width: Int,
    height: Int,
    edge: Edge,
    maxTrim: Int
) -> Int {
    let bytesPerPixel = 4
    var trimCount = 0

    switch edge {
    case .top:
        for row in 0..<min(maxTrim, height) {
            if isScanlineNearWhite(pixels: pixels, start: row * width * bytesPerPixel, count: width, stride: bytesPerPixel) {
                trimCount += 1
            } else {
                break
            }
        }

    case .bottom:
        for i in 0..<min(maxTrim, height) {
            let row = height - 1 - i
            if isScanlineNearWhite(pixels: pixels, start: row * width * bytesPerPixel, count: width, stride: bytesPerPixel) {
                trimCount += 1
            } else {
                break
            }
        }

    case .left:
        for col in 0..<min(maxTrim, width) {
            if isColumnNearWhite(pixels: pixels, col: col, width: width, height: height, bytesPerPixel: bytesPerPixel) {
                trimCount += 1
            } else {
                break
            }
        }

    case .right:
        for i in 0..<min(maxTrim, width) {
            let col = width - 1 - i
            if isColumnNearWhite(pixels: pixels, col: col, width: width, height: height, bytesPerPixel: bytesPerPixel) {
                trimCount += 1
            } else {
                break
            }
        }
    }

    return trimCount
}

// MARK: - Pixel Analysis

/// Checks whether a horizontal scanline has >= 95% near-white pixels.
private func isScanlineNearWhite(
    pixels: UnsafePointer<UInt8>,
    start: Int,
    count: Int,
    stride: Int
) -> Bool {
    var whiteCount = 0

    for i in 0..<count {
        let offset = start + i * stride
        if isNearWhite(r: pixels[offset], g: pixels[offset + 1], b: pixels[offset + 2], a: pixels[offset + 3]) {
            whiteCount += 1
        }
    }

    return Double(whiteCount) / Double(count) >= scanlineConsensus
}

/// Checks whether a vertical column has >= 95% near-white pixels.
private func isColumnNearWhite(
    pixels: UnsafePointer<UInt8>,
    col: Int,
    width: Int,
    height: Int,
    bytesPerPixel: Int
) -> Bool {
    var whiteCount = 0

    for row in 0..<height {
        let offset = (row * width + col) * bytesPerPixel
        if isNearWhite(r: pixels[offset], g: pixels[offset + 1], b: pixels[offset + 2], a: pixels[offset + 3]) {
            whiteCount += 1
        }
    }

    return Double(whiteCount) / Double(height) >= scanlineConsensus
}

/// Returns true if 95%+ of all pixels in the image are near-white.
/// Used as a safety valve to avoid trimming images with no meaningful content border.
private func isImageMostlyWhite(pixels: UnsafePointer<UInt8>, totalPixels: Int) -> Bool {
    let bytesPerPixel = 4
    var whiteCount = 0

    for i in 0..<totalPixels {
        let offset = i * bytesPerPixel
        if isNearWhite(r: pixels[offset], g: pixels[offset + 1], b: pixels[offset + 2], a: pixels[offset + 3]) {
            whiteCount += 1
        }
    }

    return Double(whiteCount) / Double(totalPixels) >= scanlineConsensus
}

/// Returns true if a pixel's RGBA channels are all >= 240.
private func isNearWhite(r: UInt8, g: UInt8, b: UInt8, a: UInt8) -> Bool {
    r >= nearWhiteMin && g >= nearWhiteMin && b >= nearWhiteMin && a >= nearWhiteMin
}
