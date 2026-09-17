//
//  AccentColorEnvironmentTests.swift
//  PlayerHeaderView
//
//  Pins what the LCD accent and offset environment values resolve to when
//  nothing is injected, and that an injected value is the one that comes back.
//
//  Characterization, not new behaviour: these defaults have always been what
//  they are here, but only `lcdActiveBrightness` was pinned anywhere (by
//  `LCDSegmentBrightnessTests`). Writing the rest down makes a change to how
//  the defaults are *declared* falsifiable — `EnvironmentValues()` reads the
//  default expression end-to-end, so a declaration that resolved to something
//  else, or a getter and setter that addressed different keys, fails here
//  rather than silently rendering a differently-colored analyzer.
//
//  Created by Jake Bromberg on 09/17/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI
import Testing
import WallpaperTheme
@testable import PlayerHeaderView

@Suite("LCD accent environment defaults")
struct AccentColorEnvironmentTests {
    /// The shipping accent: orange at 23°, normalized, three-quarters saturated
    /// and at full brightness. Asserted as literals — but not because there is
    /// nothing behind them: ``ThemeAppearance/defaultAccentColor`` is
    /// `AccentColor(hue: 23, saturation: 0.75, brightness: 1.0)`, and
    /// `normalizedHue` divides that hue by 360, so these three literals are
    /// exactly its components, copied rather than read.
    ///
    /// That copy predates this branch and stays for now; asserting the literals
    /// is what pins it. The offsets below assert against the theme's constants
    /// for the mirror-image reason — there the environment really does defer,
    /// and a literal would hide the deferral, where here reading the constant
    /// would hide the copy. Each test states the arrangement its own keys have.
    @Test("The accent defaults are the shipping normalized orange")
    func accentDefaultsAreShippingOrange() {
        let values = EnvironmentValues()

        #expect(values.lcdAccentHue == 23.0 / 360.0)
        #expect(values.lcdAccentSaturation == 0.75)
        #expect(values.lcdAccentBrightness == 1.0)
    }

    /// The offsets read the theme's constants rather than restating them, the
    /// same arrangement `lcdActiveBrightness` has with
    /// ``LCDConfiguration/defaultActiveBrightness(for:)``. Asserted against the
    /// constants for that reason: the invariant is "the environment defers to
    /// the theme", and a literal here would be the copy the deferral exists to
    /// avoid.
    @Test("The LCD offset defaults are the theme's, not private copies")
    func offsetDefaultsTrackTheTheme() {
        let values = EnvironmentValues()

        #expect(values.lcdMinOffset == HSBOffset.defaultMin)
        #expect(values.lcdMaxOffset == HSBOffset.defaultMax)
    }

    /// Guards each getter/setter pair against addressing different keys — which
    /// would route every reader back to the default and lose the injected value
    /// silently. Values are deliberately unlike any default so a read that fell
    /// through could not coincidentally match, and the two offsets are unlike
    /// *each other* so that crossing `lcdMinOffset` with `lcdMaxOffset` fails
    /// here too rather than passing on a shared value.
    @Test("An injected value is the one that resolves")
    func injectedValuesAreWhatResolve() {
        var values = EnvironmentValues()
        let minOffset = HSBOffset(hue: 12, saturation: 0.3, brightness: -0.25)
        let maxOffset = HSBOffset(hue: -7, saturation: -0.4, brightness: 0.18)

        values.lcdAccentHue = 0.5
        values.lcdAccentSaturation = 0.25
        values.lcdAccentBrightness = 0.4
        values.lcdMinOffset = minOffset
        values.lcdMaxOffset = maxOffset
        values.lcdActiveBrightness = 1.42

        #expect(values.lcdAccentHue == 0.5)
        #expect(values.lcdAccentSaturation == 0.25)
        #expect(values.lcdAccentBrightness == 0.4)
        #expect(values.lcdMinOffset == minOffset)
        #expect(values.lcdMaxOffset == maxOffset)
        #expect(values.lcdActiveBrightness == 1.42)
    }
}
