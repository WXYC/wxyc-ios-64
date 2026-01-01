//
//  BackgroundStyles.swift
//  PlayerHeaderView
//
//  Background shape styles for the player header
//

import SwiftUI

// MARK: - Header Item Background Style

/// A background style for header items with a tinted color based on theme accent.
struct HeaderItemBackgroundStyle: ShapeStyle {
    /// Hue value (0.0-1.0, already normalized)
    let hue: Double

    /// Saturation value (0.0-1.0)
    let saturation: Double

    init(hue: Double = 23.0 / 360.0, saturation: Double = 0.75) {
        self.hue = hue
        self.saturation = saturation
    }

    public func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        Color(
            hue: hue,
            saturation: saturation,
            brightness: 0.9
        )
        .opacity(0.16)
        .shadow(.inner(radius: 10))
    }
}

