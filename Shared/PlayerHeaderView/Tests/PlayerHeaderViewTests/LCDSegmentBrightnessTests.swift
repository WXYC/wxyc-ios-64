//
//  LCDSegmentBrightnessTests.swift
//  PlayerHeaderView
//
//  Tests for the LCD analyzer's lit/unlit segment brightness.
//
//  Created by Jake Bromberg on 09/16/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI
import Testing
import WallpaperTheme
@testable import PlayerHeaderView

/// Cases for ``LCDSegmentBrightnessTests/clampedAccentScalesTheMultiplier(testCase:)``,
/// hoisted out of the `@Test` attribute so the type-checker is handed an
/// annotated type rather than inferring one across a literal array of tuples.
private let segmentBrightnessClampCases: [(
    multiplier: Double,
    accentBrightness: Double,
    offsetBrightness: Double,
    expected: Double
)] = [
    // In band: the offset scales the multiplier proportionally.
    (multiplier: 1.0, accentBrightness: 1.0, offsetBrightness: -0.5, expected: 0.5),
    // Upper bound: an offset overshooting 1.0 renders as though it landed on it.
    (multiplier: 1.3, accentBrightness: 1.0, offsetBrightness: 0.5, expected: 1.3),
    // Lower bound: an offset undershooting 0 renders black, never negative.
    (multiplier: 1.3, accentBrightness: 0.2, offsetBrightness: -0.5, expected: 0.0)
]

@Suite("LCD Segment Brightness Tests")
struct LCDSegmentBrightnessTests {
    /// A lit segment renders the multiplier the theme resolved for its color
    /// scheme, unchanged.
    ///
    /// Light mode used to be scaled by a fixed `× 1.21` here: the theme produced
    /// a single dark-tuned multiplier, so the only place light could be corrected
    /// was at render time. `LCDConfiguration` now resolves the multiplier per
    /// color scheme, and `ThemeConfiguration` collapses the pair before the value
    /// reaches this view — the number arriving under a light scheme *is* the light
    /// number. Re-applying the correction would render light at `authoredLight × 1.21`
    /// — for the untuned default, far enough past 1.0 that the top of the lit range
    /// flattens onto one color. Brightness clips there; saturation does not, so at
    /// the accent's default saturation of 0.75 the segments land on a fully
    /// saturated bright accent rather than on white.
    @Test(
        "A lit segment renders exactly the multiplier resolved for its color scheme",
        arguments: [ColorScheme.light, ColorScheme.dark]
    )
    func litSegmentAppliesNoCorrection(colorScheme: ColorScheme) {
        let resolved = LCDConfiguration.defaultActiveBrightness(for: colorScheme)

        #expect(
            LCDSpectrumAnalyzerView.segmentBrightness(
                isActive: true,
                colorScheme: colorScheme,
                activeBrightnessMultiplier: resolved,
                accentBrightness: 1.0,
                offsetBrightness: 0.0
            ) == resolved
        )
    }

    /// The same holds for a value a theme authored rather than defaulted to —
    /// the view must not know or care where the multiplier came from.
    @Test("A tuned light-mode multiplier reaches the segment unscaled")
    func tunedLightMultiplierIsNotScaled() {
        let authoredLight = 1.09

        #expect(
            LCDSpectrumAnalyzerView.segmentBrightness(
                isActive: true,
                colorScheme: .light,
                activeBrightnessMultiplier: authoredLight,
                accentBrightness: 1.0,
                offsetBrightness: 0.0
            ) == authoredLight
        )
    }

    /// The unlit arm is still per-scheme and still a fixed pair — only the lit
    /// arm moved into the theme. Pinned so deleting the lit correction cannot be
    /// mistaken for deleting this one.
    ///
    /// The multiplier is `.nan` rather than a plausible brightness: this path
    /// must ignore it entirely, and a NaN that ever leaked into the result would
    /// fail the comparison below instead of quietly matching. A real-looking
    /// number here would also read as the constant this branch just single-sourced.
    @Test(
        "An unlit segment keeps its fixed per-scheme brightness",
        arguments: [
            (colorScheme: ColorScheme.light, expected: 1.15),
            (colorScheme: ColorScheme.dark, expected: 0.90)
        ]
    )
    func unlitSegmentKeepsItsFixedPair(testCase: (colorScheme: ColorScheme, expected: Double)) {
        #expect(
            LCDSpectrumAnalyzerView.segmentBrightness(
                isActive: false,
                colorScheme: testCase.colorScheme,
                activeBrightnessMultiplier: .nan,
                accentBrightness: 1.0,
                offsetBrightness: 0.0
            ) == testCase.expected
        )
    }

    /// Nothing-set default: the environment falls back to the theme's dark
    /// default rather than a literal of its own. This was the last of three
    /// hardcoded copies of `1.24` — the other two were folded into
    /// `LCDConfiguration` upstream — and a copy only stays correct until
    /// somebody retunes the constant on one side.
    @Test("The environment default is the theme's dark default, not a private copy")
    func environmentDefaultTracksTheThemeConstant() {
        #expect(
            EnvironmentValues().lcdActiveBrightness
                == LCDConfiguration.defaultActiveBrightness(for: .dark)
        )
    }

    /// The gradient offset still scales the result: a segment whose offset darkens
    /// the accent gets a proportionally dimmer lit brightness.
    ///
    /// The accent-plus-offset sum is clamped to the unit range *before* the state
    /// multiplier scales it, and both bounds are load-bearing. `HSBOffset` is
    /// author-supplied, so a manifest may push a segment's offset past either end
    /// of the accent's range; the upper bound keeps an overshooting segment from
    /// dragging the whole lit range up with it, and the lower bound keeps a
    /// negative brightness — which `Color(hue:saturation:brightness:)` has no
    /// defined behavior for — from reaching the renderer. The clamp came over
    /// from `segmentColor` unpinned by either case, so both are asserted here.
    ///
    /// Asserted under the dark scheme so it stays orthogonal to the
    /// light-correction tests above.
    @Test(
        "The clamped accent brightness scales the resolved multiplier",
        arguments: segmentBrightnessClampCases
    )
    func clampedAccentScalesTheMultiplier(
        testCase: (multiplier: Double, accentBrightness: Double, offsetBrightness: Double, expected: Double)
    ) {
        #expect(
            LCDSpectrumAnalyzerView.segmentBrightness(
                isActive: true,
                colorScheme: .dark,
                activeBrightnessMultiplier: testCase.multiplier,
                accentBrightness: testCase.accentBrightness,
                offsetBrightness: testCase.offsetBrightness
            ) == testCase.expected
        )
    }
}
