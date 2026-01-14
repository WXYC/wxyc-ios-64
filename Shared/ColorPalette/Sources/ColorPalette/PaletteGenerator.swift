//
//  PaletteGenerator.swift
//  ColorPalette
//
//  Generates harmonious color palettes (triad, complementary, analogous, etc.)
//  from a dominant color.
//
//  Created by Jake Bromberg on 12/28/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

public struct PaletteGenerator: Sendable {

    public init() {}

    /// Generates a color palette from the dominant color using the specified mode.
    public func generatePalette(from dominantColor: HSBColor, mode: PaletteMode) -> ColorPalette {
        let colors: [HSBColor]

        switch mode {
        case .triad:
            colors = generateTriad(from: dominantColor)
        case .complementary:
            colors = generateComplementary(from: dominantColor)
        case .splitComplementary:
            colors = generateSplitComplementary(from: dominantColor)
        case .square:
            colors = generateSquare(from: dominantColor)
        case .analogous:
            colors = generateAnalogous(from: dominantColor)
        }

        return ColorPalette(dominantColor: dominantColor, mode: mode, colors: colors)
    }

    // MARK: - Private Generation Methods

    private func generateTriad(from base: HSBColor) -> [HSBColor] {
        [
            base,
            base.rotatingHue(by: 120),
            base.rotatingHue(by: 240)
        ]
    }

    private func generateComplementary(from base: HSBColor) -> [HSBColor] {
        [
            base,
            base.rotatingHue(by: 180)
        ]
    }

    private func generateSplitComplementary(from base: HSBColor) -> [HSBColor] {
        [
            base,
            base.rotatingHue(by: 150),
            base.rotatingHue(by: 210)
        ]
    }

    private func generateSquare(from base: HSBColor) -> [HSBColor] {
        [
            base,
            base.rotatingHue(by: 90),
            base.rotatingHue(by: 180),
            base.rotatingHue(by: 270)
        ]
    }

    private func generateAnalogous(from base: HSBColor) -> [HSBColor] {
        [
            base.rotatingHue(by: -60),
            base.rotatingHue(by: -30),
            base,
            base.rotatingHue(by: 30),
            base.rotatingHue(by: 60)
        ]
    }
}
