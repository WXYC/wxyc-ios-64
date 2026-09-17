//
//  OnAirBannerTheme.swift
//  WXYC
//
//  Tunable visual parameters for the on-air banner, driven by the debug design controls.
//
//  Created by Jake Bromberg on 07/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import ColorPalette
import SwiftUI
import WXUI

extension Color {
    /// Creates a color from an ``HSL`` value.
    ///
    /// ColorPalette's ``HSL`` is genuine hue/saturation/lightness; SwiftUI's own
    /// `Color(hue:saturation:brightness:)` is HSB, a different space, so we convert here.
    init(_ hsl: HSL) {
        let rgb = hsl.rgb
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

/// Visual parameters for the on-air banner that the debug panel can tune live.
///
/// The ``default`` reproduces the shipping look, so release builds — which never surface
/// the debug controls — render exactly as designed. Every default here was ported
/// verbatim from `OnAirDebugState`'s persisted `UserDefaults` fallbacks (WXYC/wxyc-ios-64#752),
/// so a Release build renders exactly what shipped before this type became the source
/// of truth.
struct OnAirBannerTheme: Equatable {
    /// Color of the "ON AIR" indicator dot and its glow. Ships as a fully-saturated,
    /// medium-lightness green — HSL(0.33, 1.0, 0.5), a hair warmer than true green
    /// (1/3) — matching the value `OnAirDebugState` persisted as its default. This is
    /// deliberately *not* SwiftUI's `.green`: that system color resolves to a visibly
    /// duller, darker swatch, so hard-coding it here would have silently changed the
    /// release banner's look.
    var indicatorColor: Color = Color(HSL(hue: 0.33, saturation: 1.0, lightness: 0.5))

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
    var requestLineTintOpacity: Double = 0.75

    /// Vertical space between the "ON AIR" eyebrow and the DJ handle, in points.
    var onAirSpacing: CGFloat = 0

    /// Line spacing applied to the DJ handle, in points.
    var handleLineSpacing: CGFloat = 0

    // MARK: - Handle grade wave

    /// Whether the DJ handle plays its one-shot "wave" — a lightening crest
    /// sweeping across the letters — when it appears or changes to a new DJ. The
    /// crest dips each letter's grade and weight, but the fixed per-letter cells
    /// hold the handle's width constant, and the string starts and ends at its
    /// normal display metrics.
    var waveEnabled: Bool = true

    /// Duration of one handle-wave sweep, in seconds.
    var waveDuration: TimeInterval = 2

    /// How far, in grade units, the wave lightens a letter at the crest's peak.
    /// `0` disables the effect. The handle rests near the top of the grade range,
    /// so the wave lightens rather than darkens.
    var waveDepth: Double = 536

    /// How far, in weight (`wght`) units, the wave *also* thins a letter at the
    /// crest's peak — grade bottoms out well short of hairline, so weight carries
    /// the crest the rest of the way. `0` leaves weight alone (grade-only wave).
    /// Weight changes a glyph's advance, but the fixed per-letter cells absorb it,
    /// so the handle's total width stays constant.
    var waveWeightDepth: Double = 647

    /// The wave crest's half-width as a fraction of the handle, `(0, 1]`. Larger
    /// lights more letters at once; smaller is a tighter, crisper highlight.
    var waveCrestHalfWidth: Double = 0.75

    /// How many crests sweep across the handle per animation, `>= 1`.
    var waveRepetitions: Int = 1

    /// The launch interval between consecutive crests, as a fraction of one sweep,
    /// `(0, 1]`. `1` keeps the sweeps sequential; below `1` they overlap — several
    /// ride the handle at once and the animation finishes sooner (snappier).
    var waveSpacing: Double = 0.66

    /// A replay token: bumping it re-triggers the wave. The debug controls drive
    /// this; nothing changes it in release, so the wave only plays on appear and
    /// on handle changes there.
    var waveReplayToken: Int = 0

    static let `default` = OnAirBannerTheme()
}

// MARK: - Environment

extension EnvironmentValues {
    /// The on-air banner's visual theme. Defaults to the shipping look
    /// (``OnAirBannerTheme/default``); the composition root overrides this with a
    /// live-tuning value from the debug panel in `#if DEBUG || DEBUG_TESTFLIGHT`
    /// builds only (see `RootTabView`), so `PlaylistView` and `OnAirBannerView`
    /// never reference the debug state directly.
    @Entry var onAirBannerTheme: OnAirBannerTheme = .default
}
