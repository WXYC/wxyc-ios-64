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

    /// Minimum Delta E for colors to be considered distinct (CIE76 formula).
    private let minimumDeltaE: Double = 20.0

    /// Minimum weight ratio (relative to max) for a bin to be considered.
    private let minimumWeightRatio: Double = 0.01

    /// LAB color space for perceptual color difference calculations.
    private static let labColorSpace: CGColorSpace? = {
        var whitePoint: [CGFloat] = [0.95047, 1.0, 1.08883]
        var blackPoint: [CGFloat] = [0, 0, 0]
        var range: [CGFloat] = [-128, 128, -128, 128]
        return CGColorSpace(labWhitePoint: &whitePoint, blackPoint: &blackPoint, range: &range)
    }()

    public init() {}

    /// Represents a single bin in the HSB histogram with its weight.
    private struct HistogramBin: Comparable {
        let hueIndex: Int
        let saturationIndex: Int
        let brightnessIndex: Int
        let weight: Double

        static func < (lhs: HistogramBin, rhs: HistogramBin) -> Bool {
            lhs.weight < rhs.weight
        }
    }

    /// Extracts the dominant HSB color from the given image.
    /// - Parameter image: The source image.
    /// - Returns: The dominant HSBColor, or nil if extraction fails.
    public func extractDominantColor(from image: Image) -> HSBColor? {
        extractDominantColors(from: image, count: 1).first
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

    // MARK: - Multi-Color Extraction

    /// Extracts up to `count` dominant HSB colors from the given image.
    /// Colors are selected to be perceptually distinct using CIELAB color difference.
    /// - Parameters:
    ///   - image: The source image.
    ///   - count: Maximum number of colors to extract.
    /// - Returns: Array of distinct HSBColors, may be fewer than `count` if not enough distinct colors exist.
    public func extractDominantColors(from image: Image, count: Int) -> [HSBColor] {
        guard count > 0 else { return [] }
        guard let cgImage = downsampledCGImage(from: image) else { return [] }

        let width = cgImage.width
        let height = cgImage.height

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

        guard error == kvImageNoError else { return [] }

        let histogram = buildHSBHistogram(from: sourceBuffer, width: width, height: height)
        let candidates = extractSortedCandidates(from: histogram)

        return selectDistinctColors(from: candidates, targetCount: count)
    }

    /// Extracts all non-trivial histogram bins, sorted by weight descending.
    private func extractSortedCandidates(from histogram: [[[Double]]]) -> [HistogramBin] {
        var bins: [HistogramBin] = []
        var maxWeight = 0.0

        // Find max weight first
        for h in 0..<hueBins {
            for s in 0..<saturationBins {
                for b in 0..<brightnessBins {
                    maxWeight = max(maxWeight, histogram[h][s][b])
                }
            }
        }

        let threshold = maxWeight * minimumWeightRatio

        // Collect bins above threshold
        for h in 0..<hueBins {
            for s in 0..<saturationBins {
                for b in 0..<brightnessBins {
                    let weight = histogram[h][s][b]
                    if weight >= threshold {
                        bins.append(HistogramBin(
                            hueIndex: h,
                            saturationIndex: s,
                            brightnessIndex: b,
                            weight: weight
                        ))
                    }
                }
            }
        }

        return bins.sorted(by: >)
    }

    /// Converts a histogram bin to an HSBColor using bin center values.
    private func binToHSBColor(_ bin: HistogramBin) -> HSBColor {
        let hue = (Double(bin.hueIndex) + 0.5) / Double(hueBins) * 360.0
        let saturation = (Double(bin.saturationIndex) + 0.5) / Double(saturationBins)
        let brightness = (Double(bin.brightnessIndex) + 0.5) / Double(brightnessBins)
        return HSBColor(hue: hue, saturation: saturation, brightness: brightness)
    }

    /// Selects up to `targetCount` colors that are perceptually distinct.
    private func selectDistinctColors(from candidates: [HistogramBin], targetCount: Int) -> [HSBColor] {
        var selected: [HSBColor] = []
        var selectedLAB: [(l: CGFloat, a: CGFloat, b: CGFloat)] = []

        for bin in candidates {
            if selected.count >= targetCount { break }

            let color = binToHSBColor(bin)
            guard let lab = toLABComponents(color) else { continue }

            // Check if this color is sufficiently different from all selected colors
            let isDistinct = selectedLAB.allSatisfy { existing in
                deltaE(lab, existing) >= minimumDeltaE
            }

            if isDistinct {
                selected.append(color)
                selectedLAB.append(lab)
            }
        }

        return selected
    }

    /// Converts an HSBColor to CIELAB components for perceptual comparison.
    private func toLABComponents(_ color: HSBColor) -> (l: CGFloat, a: CGFloat, b: CGFloat)? {
        guard let labColorSpace = Self.labColorSpace else { return nil }

        #if canImport(UIKit)
        let uiColor = color.uiColor
        let cgColor = uiColor.cgColor
        guard let labColor = cgColor.converted(to: labColorSpace, intent: .defaultIntent, options: nil),
              let components = labColor.components,
              components.count >= 3 else { return nil }
        return (components[0], components[1], components[2])
        #elseif canImport(AppKit)
        let nsColor = color.nsColor
        let cgColor = nsColor.cgColor
        guard let labColor = cgColor.converted(to: labColorSpace, intent: .defaultIntent, options: nil),
              let components = labColor.components,
              components.count >= 3 else { return nil }
        return (components[0], components[1], components[2])
        #endif
    }

    /// Calculates Delta E (CIE76) between two LAB colors.
    private func deltaE(
        _ lab1: (l: CGFloat, a: CGFloat, b: CGFloat),
        _ lab2: (l: CGFloat, a: CGFloat, b: CGFloat)
    ) -> Double {
        let dl = Double(lab1.l - lab2.l)
        let da = Double(lab1.a - lab2.a)
        let db = Double(lab1.b - lab2.b)
        return sqrt(dl * dl + da * da + db * db)
    }
}
