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

    /// The SF Pro variable-font axes applied to the DJ handle.
    var handleVariation: SFProVariation = SFProVariation()

    /// Vertical space between the "ON AIR" eyebrow and the DJ handle, in points.
    var onAirSpacing: CGFloat = 0

    /// Line spacing applied to the DJ handle, in points.
    var handleLineSpacing: CGFloat = 0

    static let `default` = OnAirBannerTheme()
}
