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

@Suite("LCD Segment Brightness Tests")
@MainActor
struct LCDSegmentBrightnessTests {
    /// A lit segment renders the multiplier the theme resolved for its color
    /// scheme, unchanged.
    ///
    /// Light mode used to be scaled by a fixed `× 1.21` here: the theme produced
    /// a single dark-tuned multiplier, so the only place light could be corrected
    /// was at render time. `LCDConfiguration` now resolves the multiplier per
    /// color scheme, and `ThemeConfiguration` collapses the pair before the value
    /// reaches this view — the number arriving under a light scheme *is* the light
    /// number. Re-applying the correction would render light at `authoredLight × 1.21`,
    /// which for the untuned default clips to white.
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
                activeBrightnessMultiplier: 1.24,
                accentBrightness: 1.0,
                offsetBrightness: 0.0
            ) == testCase.expected
        )
    }

    /// The gradient offset still scales the result: a segment whose offset darkens
    /// the accent gets a proportionally dimmer lit brightness. Asserted under the
    /// dark scheme so it stays orthogonal to the light-correction tests above.
    @Test("The gradient offset scales the resolved multiplier")
    func offsetScalesTheMultiplier() {
        #expect(
            LCDSpectrumAnalyzerView.segmentBrightness(
                isActive: true,
                colorScheme: .dark,
                activeBrightnessMultiplier: 1.0,
                accentBrightness: 1.0,
                offsetBrightness: -0.5
            ) == 0.5
        )
    }
}
