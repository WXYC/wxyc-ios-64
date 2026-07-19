//
//  OnAirBannerTheme.swift
//  WXYC
//
//  Tunable visual parameters for the on-air banner, driven by the debug design controls.
//
//  Created by Jake Bromberg on 07/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Playlist
import SwiftUI

extension Color {
    /// Creates a color from an ``HSL`` value.
    ///
    /// Playlist's ``HSL`` is genuine hue/saturation/lightness; SwiftUI's own
    /// `Color(hue:saturation:brightness:)` is HSB, a different space, so we convert here.
    init(_ hsl: HSL) {
        let rgb = hsl.rgb
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

/// Visual parameters for the on-air banner that the debug panel can tune live.
///
/// The ``default`` reproduces the shipping look, so release builds — which never surface
/// the debug controls — render exactly as designed.
struct OnAirBannerTheme: Equatable {
    /// Color of the "ON AIR" indicator dot and its glow.
    var indicatorColor: Color = .green

    /// Blur radius of the indicator's glow, in points.
    var indicatorBlurRadius: CGFloat = 4.5

    /// The SF Pro variable-font axes applied to the DJ handle. Its `width` is the
    /// base (expanded) axis; when ``adaptiveWidth`` is on, the banner narrows it
    /// per-handle down to ``handleWidthFloor`` to keep long names on one line.
    var handleVariation: SFProVariation = SFProVariation()

    /// Whether the DJ handle condenses its width axis to fit one line beside the
    /// say-hi chip. On by default — the shipping behavior.
    var adaptiveWidth: Bool = true

    /// The narrowest width axis the adaptive fit will use before letting the
    /// handle wrap. SF Pro stays legible down into its condensed widths, so this
    /// can sit low; past it, an enormous handle wraps rather than over-squishing.
    var handleWidthFloor: Double = 50

    /// Opacity of the say-hi chip's green glass tint, `0...1`. Controls how
    /// transparent the capsule background is; the chip's text and icon stay
    /// opaque, so only the background fades. Ships slightly translucent so the
    /// wallpaper reads through the chip.
    var sayHiTintOpacity: Double = 0.75

    /// Vertical space between the "ON AIR" eyebrow and the DJ handle, in points.
    var onAirSpacing: CGFloat = 0

    /// Line spacing applied to the DJ handle, in points.
    var handleLineSpacing: CGFloat = 0

    static let `default` = OnAirBannerTheme()
}
