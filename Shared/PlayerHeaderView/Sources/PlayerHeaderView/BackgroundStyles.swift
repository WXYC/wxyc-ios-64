//
//  BackgroundStyles.swift
//  PlayerHeaderView
//
//  Background shape styles for the player header
//
//  Created by Jake Bromberg on 11/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI

// MARK: - Header Item Background Style

/// A background style for header items with a tinted color based on theme accent.
/// Reads accent color from the environment so it updates when the theme changes.
struct HeaderItemBackgroundStyle: ShapeStyle {
    public func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        Color(
            hue: environment.lcdAccentHue,
            saturation: environment.lcdAccentSaturation,
            brightness: 0.9
        )
        .opacity(0.16)
        .shadow(.inner(radius: 10))
    }
}
