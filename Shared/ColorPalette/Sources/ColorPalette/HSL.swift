//
//  HSL.swift
//  ColorPalette
//
//  A hue/saturation/lightness color used by the on-air banner theme controls.
//
//  Created by Jake Bromberg on 07/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

// MARK: - HSL

/// A color expressed in the HSL (hue, saturation, lightness) space.
///
/// The debug banner controls tune the "on air" indicator in HSL because it maps cleanly
/// onto three intuitive sliders. The view layer converts ``rgb`` into a SwiftUI `Color`.
/// SwiftUI's own `Color(hue:saturation:brightness:)` is HSB — a different space — so the
/// conversion lives here rather than being delegated to it.
///
/// ``HSBColor`` also lives in this package, and deliberately stays a separate type rather
/// than folding into this one: the two exist for different jobs. HSBColor bridges to
/// UIKit/AppKit (``HSBColor/uiColor``, ``HSBColor/nsColor``) and carries the wallpaper
/// theming system's semantic operations (``HSBColor/rotatingHue(by:)``,
/// ``HSBColor/withBrightness(_:)``), with hue in degrees to match `UIColor`'s own
/// convention. HSL exists to translate design-system colors specified as CSS `hsl()`
/// values (see `BoxOfficeTicketView` and `OnTourRowBadge`, both transcribing literal
/// prototype CSS) and to back the on-air banner's fraction-based debug sliders — CSS's
/// hue is a fraction of the wheel, not degrees, and its "lightness" is a different
/// midpoint-anchored model than HSB's "brightness." Unifying them would mean either
/// picking one convention and re-deriving every transcribed CSS value and slider by
/// hand, or keeping both formulas under one type — neither buys anything over two small,
/// independently-correct structs. Consolidating them into one *package* (this ticket)
/// still gets the win that mattered: one place to look for "how does this codebase turn
/// hue+something+something into a Color," instead of the previous split across Playlist
/// and ColorPalette.
public struct HSL: Hashable, Sendable {
    /// Hue as a fraction of the color wheel, `0...1` (0 = red, 1/3 = green, 2/3 = blue).
    public var hue: Double
    /// Saturation, `0...1` (0 = gray, 1 = fully saturated).
    public var saturation: Double
    /// Lightness, `0...1` (0 = black, 0.5 = pure hue, 1 = white).
    public var lightness: Double

    public init(hue: Double, saturation: Double, lightness: Double) {
        self.hue = hue
        self.saturation = saturation
        self.lightness = lightness
    }

    /// The equivalent RGB components, each in `0...1`.
    public var rgb: (red: Double, green: Double, blue: Double) {
        guard saturation != 0 else {
            return (lightness, lightness, lightness)
        }
        let q = lightness < 0.5
            ? lightness * (1 + saturation)
            : lightness + saturation - lightness * saturation
        let p = 2 * lightness - q
        return (
            red: Self.component(p, q, hue + 1.0 / 3.0),
            green: Self.component(p, q, hue),
            blue: Self.component(p, q, hue - 1.0 / 3.0)
        )
    }

    /// Resolves a single RGB channel from the intermediate `p`/`q` and a hue offset.
    private static func component(_ p: Double, _ q: Double, _ t: Double) -> Double {
        var t = t
        if t < 0 { t += 1 }
        if t > 1 { t -= 1 }
        if t < 1.0 / 6.0 { return p + (q - p) * 6 * t }
        if t < 1.0 / 2.0 { return q }
        if t < 2.0 / 3.0 { return p + (q - p) * (2.0 / 3.0 - t) * 6 }
        return p
    }
}
