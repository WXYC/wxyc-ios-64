import Accelerate
import Core

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Extracts the dominant color from an image using vImage histogram analysis.
public struct DominantColorExtractor: Sendable {
    /// Number of histogram bins for hue (10-degree resolution).
    private let hueBins = 36

    /// Number of histogram bins for saturation (10% resolution).
    private let saturationBins = 10

    /// Number of histogram bins for brightness (10% resolution).
    private let brightnessBins = 10

    /// Maximum dimension for downsampling (improves performance on large images).
    private let maxDimension = 100

    public init() {}

    /// Extracts the dominant HSB color from the given image.
    /// - Parameter image: The source image.
    /// - Returns: The dominant HSBColor, or nil if extraction fails.
    public func extractDominantColor(from image: Image) -> HSBColor? {
        guard let cgImage = downsampledCGImage(from: image) else { return nil }

        let width = cgImage.width
        let height = cgImage.height

        // Create vImage buffer
        var sourceBuffer = vImage_Buffer()
        defer { free(sourceBuffer.data) }

        var format = vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            colorSpace: nil,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue),
            version: 0,
            decode: nil,
            renderingIntent: .defaultIntent
        )

        let error = vImageBuffer_InitWithCGImage(
            &sourceBuffer,
            &format,
            nil,
            cgImage,
            vImage_Flags(kvImageNoFlags)
        )

        guard error == kvImageNoError else { return nil }

        // Build HSB histogram
        let histogram = buildHSBHistogram(from: sourceBuffer, width: width, height: height)

        // Find dominant color from histogram
        return findDominantColor(in: histogram)
    }

    // MARK: - Private Methods

    private func downsampledCGImage(from image: Image) -> CGImage? {
        #if canImport(UIKit)
        guard let cgImage = image.cgImage else { return nil }
        #elseif canImport(AppKit)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        #endif

        let width = cgImage.width
        let height = cgImage.height

        // Skip downsampling if already small enough
        if width <= maxDimension && height <= maxDimension {
            return cgImage
        }

        // Calculate scaled dimensions
        let scale = Double(maxDimension) / Double(max(width, height))
        let newWidth = Int(Double(width) * scale)
        let newHeight = Int(Double(height) * scale)

        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }

        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

        return context.makeImage()
    }

    private func buildHSBHistogram(
        from buffer: vImage_Buffer,
        width: Int,
        height: Int
    ) -> [[[Double]]] {
        // 3D array: [hue][saturation][brightness] -> weighted count
        var histogram = Array(
            repeating: Array(
                repeating: Array(repeating: 0.0, count: brightnessBins),
                count: saturationBins
            ),
            count: hueBins
        )

        let pixels = buffer.data.assumingMemoryBound(to: UInt8.self)
        let rowBytes = buffer.rowBytes

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * rowBytes + x * 4

                // ARGB format (premultiplied first)
                let a = Double(pixels[offset]) / 255.0
                let r = Double(pixels[offset + 1]) / 255.0
                let g = Double(pixels[offset + 2]) / 255.0
                let b = Double(pixels[offset + 3]) / 255.0

                // Skip transparent pixels
                guard a > 0.1 else { continue }

                // Convert RGB to HSB
                let (h, s, v) = rgbToHSB(r: r, g: g, b: b)

                // Calculate weight - reduce influence of desaturated and extreme brightness
                let saturationWeight = s
                let brightnessWeight = 1.0 - abs(v - 0.5) * 2.0
                let weight = saturationWeight * max(brightnessWeight, 0.1)

                // Skip near-grayscale pixels
                guard weight > 0.05 else { continue }

                // Map to bins
                let hueBin = min(Int((h / 360.0) * Double(hueBins)), hueBins - 1)
                let satBin = min(Int(s * Double(saturationBins)), saturationBins - 1)
                let briBin = min(Int(v * Double(brightnessBins)), brightnessBins - 1)

                histogram[hueBin][satBin][briBin] += weight
            }
        }

        return histogram
    }

    private func rgbToHSB(r: Double, g: Double, b: Double) -> (h: Double, s: Double, b: Double) {
        let maxVal = max(r, g, b)
        let minVal = min(r, g, b)
        let delta = maxVal - minVal

        // Brightness
        let brightness = maxVal

        // Saturation
        let saturation = maxVal == 0 ? 0 : delta / maxVal

        // Hue
        var hue: Double = 0
        if delta != 0 {
            switch maxVal {
            case r:
                hue = 60 * (((g - b) / delta).truncatingRemainder(dividingBy: 6))
            case g:
                hue = 60 * (((b - r) / delta) + 2)
            case b:
                hue = 60 * (((r - g) / delta) + 4)
            default:
                break
            }
        }

        if hue < 0 { hue += 360 }

        return (hue, saturation, brightness)
    }

    private func findDominantColor(in histogram: [[[Double]]]) -> HSBColor {
        var maxWeight = 0.0
        var dominantBin = (h: 0, s: 0, b: 0)

        for h in 0..<hueBins {
            for s in 0..<saturationBins {
                for b in 0..<brightnessBins {
                    if histogram[h][s][b] > maxWeight {
                        maxWeight = histogram[h][s][b]
                        dominantBin = (h, s, b)
                    }
                }
            }
        }

        // Convert bin indices back to HSB values (use center of bin)
        let hue = (Double(dominantBin.h) + 0.5) / Double(hueBins) * 360.0
        let saturation = (Double(dominantBin.s) + 0.5) / Double(saturationBins)
        let brightness = (Double(dominantBin.b) + 0.5) / Double(brightnessBins)

        return HSBColor(hue: hue, saturation: saturation, brightness: brightness)
    }
}
