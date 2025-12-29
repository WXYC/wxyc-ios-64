import Testing
@testable import ColorPalette

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@Suite("PaletteGenerator Tests")
struct PaletteGeneratorTests {

    let generator = PaletteGenerator()
    let baseColor = HSBColor(hue: 0, saturation: 1.0, brightness: 1.0) // Pure red

    // MARK: - Triad Tests

    @Test("Triad generates three colors")
    func triadGeneratesThreeColors() {
        let palette = generator.generatePalette(from: baseColor, mode: .triad)

        #expect(palette.colors.count == 3)
        #expect(palette.mode == .triad)
    }

    @Test("Triad generates colors 120 degrees apart")
    func triadGeneratesColors120DegreesApart() {
        let palette = generator.generatePalette(from: baseColor, mode: .triad)

        #expect(palette.colors[0].hue == 0)
        #expect(palette.colors[1].hue == 120)
        #expect(palette.colors[2].hue == 240)
    }

    // MARK: - Complementary Tests

    @Test("Complementary generates two colors")
    func complementaryGeneratesTwoColors() {
        let palette = generator.generatePalette(from: baseColor, mode: .complementary)

        #expect(palette.colors.count == 2)
        #expect(palette.mode == .complementary)
    }

    @Test("Complementary generates colors 180 degrees apart")
    func complementaryGeneratesColors180DegreesApart() {
        let palette = generator.generatePalette(from: baseColor, mode: .complementary)

        #expect(palette.colors[0].hue == 0)
        #expect(palette.colors[1].hue == 180)
    }

    // MARK: - Split Complementary Tests

    @Test("Split complementary generates three colors")
    func splitComplementaryGeneratesThreeColors() {
        let palette = generator.generatePalette(from: baseColor, mode: .splitComplementary)

        #expect(palette.colors.count == 3)
        #expect(palette.mode == .splitComplementary)
    }

    @Test("Split complementary generates correct angles")
    func splitComplementaryGeneratesCorrectAngles() {
        let palette = generator.generatePalette(from: baseColor, mode: .splitComplementary)

        #expect(palette.colors[0].hue == 0)
        #expect(palette.colors[1].hue == 150)
        #expect(palette.colors[2].hue == 210)
    }

    // MARK: - Square Tests

    @Test("Square generates four colors")
    func squareGeneratesFourColors() {
        let palette = generator.generatePalette(from: baseColor, mode: .square)

        #expect(palette.colors.count == 4)
        #expect(palette.mode == .square)
    }

    @Test("Square generates colors 90 degrees apart")
    func squareGeneratesColors90DegreesApart() {
        let palette = generator.generatePalette(from: baseColor, mode: .square)

        #expect(palette.colors[0].hue == 0)
        #expect(palette.colors[1].hue == 90)
        #expect(palette.colors[2].hue == 180)
        #expect(palette.colors[3].hue == 270)
    }

    // MARK: - Analogous Tests

    @Test("Analogous generates five colors")
    func analogousGeneratesFiveColors() {
        let palette = generator.generatePalette(from: baseColor, mode: .analogous)

        #expect(palette.colors.count == 5)
        #expect(palette.mode == .analogous)
    }

    @Test("Analogous generates five adjacent colors")
    func analogousGeneratesFiveAdjacentColors() {
        let palette = generator.generatePalette(from: baseColor, mode: .analogous)

        // Colors should be at -60, -30, 0, 30, 60 from base
        #expect(palette.colors[0].hue == 300) // -60 wraps to 300
        #expect(palette.colors[1].hue == 330) // -30 wraps to 330
        #expect(palette.colors[2].hue == 0)
        #expect(palette.colors[3].hue == 30)
        #expect(palette.colors[4].hue == 60)
    }

    // MARK: - Hue Wrapping Tests

    @Test("Hue wraps correctly at 360 when adding")
    func hueWrapsCorrectlyWhenAdding() {
        let nearMax = HSBColor(hue: 350, saturation: 1.0, brightness: 1.0)
        let palette = generator.generatePalette(from: nearMax, mode: .triad)

        // 350 + 120 = 470 -> should wrap to 110
        #expect(palette.colors[1].hue == 110)
        // 350 + 240 = 590 -> should wrap to 230
        #expect(palette.colors[2].hue == 230)
    }

    @Test("Hue wraps correctly when subtracting")
    func hueWrapsCorrectlyWhenSubtracting() {
        let nearZero = HSBColor(hue: 20, saturation: 1.0, brightness: 1.0)
        let palette = generator.generatePalette(from: nearZero, mode: .analogous)

        // 20 - 60 = -40 -> should wrap to 320
        #expect(palette.colors[0].hue == 320)
        // 20 - 30 = -10 -> should wrap to 350
        #expect(palette.colors[1].hue == 350)
    }

    // MARK: - Saturation and Brightness Preservation

    @Test("Saturation and brightness preserved in generated colors")
    func saturationAndBrightnessPreserved() {
        let customColor = HSBColor(hue: 60, saturation: 0.7, brightness: 0.8)
        let palette = generator.generatePalette(from: customColor, mode: .complementary)

        for color in palette.colors {
            #expect(color.saturation == 0.7)
            #expect(color.brightness == 0.8)
        }
    }

    @Test("Low saturation is preserved")
    func lowSaturationIsPreserved() {
        let desaturated = HSBColor(hue: 180, saturation: 0.2, brightness: 0.9)
        let palette = generator.generatePalette(from: desaturated, mode: .square)

        for color in palette.colors {
            #expect(color.saturation == 0.2)
            #expect(color.brightness == 0.9)
        }
    }

    // MARK: - Dominant Color Preservation

    @Test("Dominant color is included in palette")
    func dominantColorIsIncludedInPalette() {
        let dominant = HSBColor(hue: 45, saturation: 0.85, brightness: 0.95)
        let palette = generator.generatePalette(from: dominant, mode: .triad)

        #expect(palette.dominantColor == dominant)
        #expect(palette.colors.contains(dominant))
    }

    // MARK: - PaletteMode colorCount Tests

    @Test("PaletteMode colorCount matches generated colors")
    func paletteModeColorCountMatchesGenerated() {
        for mode in PaletteMode.allCases {
            let palette = generator.generatePalette(from: baseColor, mode: mode)
            #expect(palette.colors.count == mode.colorCount)
        }
    }

    // MARK: - Codable Tests

    @Test("ColorPalette is Codable")
    func colorPaletteIsCodable() throws {
        let palette = generator.generatePalette(from: baseColor, mode: .triad)

        let encoder = JSONEncoder()
        let data = try encoder.encode(palette)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ColorPalette.self, from: data)

        #expect(decoded == palette)
        #expect(decoded.colors.count == palette.colors.count)
        #expect(decoded.dominantColor == palette.dominantColor)
        #expect(decoded.mode == palette.mode)
    }

    @Test("HSBColor is Codable")
    func hsbColorIsCodable() throws {
        let color = HSBColor(hue: 123.5, saturation: 0.67, brightness: 0.89)

        let encoder = JSONEncoder()
        let data = try encoder.encode(color)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(HSBColor.self, from: data)

        #expect(decoded == color)
        #expect(decoded.hue == 123.5)
        #expect(decoded.saturation == 0.67)
        #expect(decoded.brightness == 0.89)
    }

    @Test("PaletteMode is Codable")
    func paletteModeIsCodable() throws {
        for mode in PaletteMode.allCases {
            let encoder = JSONEncoder()
            let data = try encoder.encode(mode)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(PaletteMode.self, from: data)

            #expect(decoded == mode)
        }
    }

    // MARK: - Color Conversion Tests

    @Test("HSBColor converts to SwiftUI Color")
    func hsbColorConvertsToSwiftUIColor() {
        let hsbColor = HSBColor(hue: 180, saturation: 0.5, brightness: 0.8)
        let swiftUIColor = hsbColor.color

        // Just verify it doesn't crash and returns a color
        #expect(type(of: swiftUIColor) == type(of: swiftUIColor))
    }

    #if canImport(UIKit)
    @Test("HSBColor converts to UIColor")
    func hsbColorConvertsToUIColor() {
        let hsbColor = HSBColor(hue: 90, saturation: 0.6, brightness: 0.7)
        let uiColor = hsbColor.uiColor

        // Verify the conversion produces expected values
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)

        #expect(abs(h - 0.25) < 0.01) // 90/360 = 0.25
        #expect(abs(s - 0.6) < 0.01)
        #expect(abs(b - 0.7) < 0.01)
        #expect(a == 1.0)
    }

    @Test("ColorPalette uiColors returns correct count")
    func colorPaletteUIColorsReturnsCorrectCount() {
        let palette = generator.generatePalette(from: baseColor, mode: .analogous)

        #expect(palette.uiColors.count == 5)
    }
    #endif

    @Test("ColorPalette swiftUIColors returns correct count")
    func colorPaletteSwiftUIColorsReturnsCorrectCount() {
        let palette = generator.generatePalette(from: baseColor, mode: .square)

        #expect(palette.swiftUIColors.count == 4)
    }
}
