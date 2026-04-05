//
//  ColorPaletteCacheKey.swift
//  ColorPalette
//
//  Cache key generation for color palette data. Follows the MetadataCacheKey pattern
//  to provide consistent, namespaced cache keys.
//
//  Created by Jake Bromberg on 03/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

/// Utility for generating consistent cache keys for color palettes.
///
/// Palette cache keys incorporate both the generation mode and the source identifier
/// (typically an artist-album pair) to avoid collisions between different palettes
/// generated from the same artwork.
public enum ColorPaletteCacheKey {

    /// Cache key for a color palette extracted from artwork.
    ///
    /// - Parameters:
    ///   - mode: The palette generation mode (triad, complementary, etc.)
    ///   - identifier: A unique identifier for the source image (typically artist-album)
    /// - Returns: Cache key in format `palette-{mode}-{identifier}`
    public static func palette(mode: PaletteMode, identifier: String) -> String {
        "palette-\(mode.rawValue)-\(identifier)"
    }
}
