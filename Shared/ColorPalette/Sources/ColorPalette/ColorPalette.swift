//
//  ColorPalette.swift
//  ColorPalette
//
//  Data model for generated color palettes derived from dominant colors.
//
//  Created by Jake Bromberg on 12/28/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A generated color palette derived from a dominant color.
public struct ColorPalette: Codable, Hashable, Sendable {
    /// The dominant color extracted from the source image.
    public let dominantColor: HSBColor

    /// The mode used to generate this palette.
    public let mode: PaletteMode

    /// The generated palette colors (includes dominant color).
    public let colors: [HSBColor]

    public init(dominantColor: HSBColor, mode: PaletteMode, colors: [HSBColor]) {
        self.dominantColor = dominantColor
        self.mode = mode
        self.colors = colors
    }

    /// Convenience accessor for SwiftUI colors.
    public var swiftUIColors: [Color] {
        colors.map(\.color)
    }

    #if canImport(UIKit)
    /// Convenience accessor for UIKit colors.
    public var uiColors: [UIColor] {
        colors.map(\.uiColor)
    }
    #elseif canImport(AppKit)
    /// Convenience accessor for AppKit colors.
    public var nsColors: [NSColor] {
        colors.map(\.nsColor)
    }
    #endif
}
