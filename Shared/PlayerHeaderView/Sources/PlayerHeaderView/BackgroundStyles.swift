//
//  BackgroundStyles.swift
//  PlayerHeaderView
//
//  Background shape styles for the player header
//

import SwiftUI
import Wallpaper

// MARK: - WXYC Background

/// Type alias to the canonical WXYCGradientWallpaper from Wallpaper package
typealias WXYCBackground = WXYCGradientWallpaper

// MARK: - Header Item Background Style

/// A background style for header items with an orange tint
struct HeaderItemBackgroundStyle: ShapeStyle {
    init() {}
    
    public func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        Color(
            hue: 23.0 / 360.0,
            saturation: 0.75,
            brightness: 0.9
        )
        .opacity(0.16)
        .shadow(.inner(radius: 10))
    }
}

