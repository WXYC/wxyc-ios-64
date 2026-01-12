import SwiftUI

/// Interpolates a small set of dominant colors to 16 colors for MeshGradient.
public struct MeshGradientPaletteInterpolator: Sendable {
    private let paletteGenerator = PaletteGenerator()

    public init() {}

    /// Interpolates 3-5 HSB colors to exactly 16 SwiftUI Colors for use in MeshGradient.
    ///
    /// Uses `PaletteGenerator` to create harmonious analogous variations of each dominant color,
    /// then adds brightness variations to fill the 16-color requirement.
    ///
    /// - Parameter dominantColors: Array of 3-5 dominant colors extracted from an image.
    /// - Returns: Array of exactly 16 SwiftUI Colors suitable for MeshGradient.
    public func interpolate(_ dominantColors: [HSBColor]) -> [Color] {
        guard !dominantColors.isEmpty else {
            return []
        }

        var colors: [HSBColor] = []

        // For each dominant color, generate analogous palette (5 colors each)
        for dominant in dominantColors {
            let analogous = paletteGenerator.generatePalette(from: dominant, mode: .complementary)
            colors.append(contentsOf: analogous.colors)
        }

        // Add brightness variations of the original dominant colors
        for dominant in dominantColors {
            // Lighter variant
            let lighterBrightness = min(dominant.brightness + 0.15, 1.0)
            colors.append(dominant.withBrightness(lighterBrightness))

            // Darker variant
            let darkerBrightness = max(dominant.brightness - 0.15, 0.0)
            colors.append(dominant.withBrightness(darkerBrightness))
        }

        // Shuffle to distribute similar colors across the mesh grid
        let shuffled = colors.shuffled()

        // Take exactly 16 colors, padding with repeats if necessary
        var result: [HSBColor] = []
        for i in 0..<16 {
            result.append(shuffled[i % shuffled.count])
        }

        return result.map(\.color)
    }
}
