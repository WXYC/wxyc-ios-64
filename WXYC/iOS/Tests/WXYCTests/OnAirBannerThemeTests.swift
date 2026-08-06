//
//  OnAirBannerThemeTests.swift
//  WXYC
//
//  Golden-table test for OnAirBannerTheme.default. Since WXYC/wxyc-ios-64#752,
//  OnAirBannerTheme.default is the sole source of the release banner's appearance —
//  PlaylistView reads it (via the environment) with no debug fallback in Release — so
//  nothing else enforces that it stays byte-equal to the shipping look. This asserts
//  every field against its literal value, so a future edit to OnAirBannerTheme.swift
//  that accidentally drifts one field (the exact failure mode this ticket exists to
//  kill) fails loudly here instead of silently shipping.
//
//  This is deliberately a golden-literal test, not a cross-table parity test against
//  OnAirDebugState's init fallbacks (Shared/DebugPanel/Sources/DebugPanel/OnAirDebugState.swift).
//  OnAirDebugState.shared is a lazily-initialized singleton seeded from the host
//  process's real UserDefaults, so it has no fixed literal a test can assert against —
//  a parity test against it isn't cleanly writable today. The durable fix is #767:
//  make OnAirDebugState seed *from* OnAirBannerTheme.default, which deletes that
//  second table (and the drift risk) entirely.
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import SwiftUI
import WXUI
@testable import WXYC

@Suite("OnAirBannerTheme")
struct OnAirBannerThemeTests {
    @Test("default matches the shipping banner's look, field by field")
    func defaultMatchesShippingLook() {
        let theme = OnAirBannerTheme.default

        #expect(theme.indicatorColor == Color(HSL(hue: 0.33, saturation: 1.0, lightness: 0.5)))
        #expect(theme.indicatorBlurRadius == 4.5)
        #expect(theme.handleVariation == SFProVariation(weight: 648, width: 150, opticalSize: 17, grade: 936))
        #expect(theme.adaptiveWidth == true)
        #expect(theme.handleWidthFloor == 50)
        #expect(theme.requestLineTintOpacity == 0.75)
        #expect(theme.onAirSpacing == 0)
        #expect(theme.handleLineSpacing == 0)
        #expect(theme.waveEnabled == true)
        #expect(theme.waveDuration == 2)
        #expect(theme.waveDepth == 536)
        #expect(theme.waveWeightDepth == 647)
        #expect(theme.waveCrestHalfWidth == 0.75)
        #expect(theme.waveRepetitions == 1)
        #expect(theme.waveSpacing == 0.66)
        #expect(theme.waveReplayToken == 0)
    }

    @Test("indicatorColor is deliberately not SwiftUI's .green")
    func indicatorColorIsNotSystemGreen() {
        // Regression guard for the bug this ticket fixed: .green is a visibly duller,
        // darker system color than the fully-saturated HSL green OnAirDebugState
        // actually shipped as its default.
        #expect(OnAirBannerTheme.default.indicatorColor != Color.green)
    }
}
