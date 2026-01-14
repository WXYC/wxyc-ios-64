//
//  PaletteMode.swift
//  ColorPalette
//
//  Enumeration of color harmony modes (triad, complementary, analogous, etc.).
//
//  Created by Jake Bromberg on 12/28/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

public enum PaletteMode: String, Codable, CaseIterable, Sendable {
    /// Three colors, 120 degrees apart on the color wheel.
    case triad

    /// Two colors, 180 degrees apart (opposite on the wheel).
    case complementary

    /// Three colors: base + two colors 150 and 210 degrees from base.
    case splitComplementary

    /// Four colors, 90 degrees apart.
    case square

    /// Colors adjacent on the wheel (base + two on each side at 30-degree intervals).
    case analogous

    /// Number of colors this mode produces.
    public var colorCount: Int {
        switch self {
        case .complementary: 2
        case .triad, .splitComplementary: 3
        case .square: 4
        case .analogous: 5
        }
    }
}
