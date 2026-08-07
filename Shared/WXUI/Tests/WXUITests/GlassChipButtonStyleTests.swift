//
//  GlassChipButtonStyleTests.swift
//  WXUI
//
//  Tests over GlassChipButtonStyle's canon fill/stroke constants — the pure
//  logic behind the chrome. The rendered view itself isn't inspectable without
//  a snapshot/inspection dependency this package deliberately doesn't take on,
//  so these tests target the values that drive it.
//
//  Created by Jake Bromberg on 08/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI
import Testing
@testable import WXUI

@Suite("GlassChipButtonStyle")
struct GlassChipButtonStyleTests {
    @Test("canon fill opacity is 0.16")
    func fillOpacity() {
        #expect(GlassChipButtonStyle.fillOpacity == 0.16)
    }

    @Test("canon stroke opacity is 0.25")
    func strokeOpacity() {
        #expect(GlassChipButtonStyle.strokeOpacity == 0.25)
    }

    @Test("canon stroke width is 1pt")
    func strokeWidth() {
        #expect(GlassChipButtonStyle.strokeWidth == 1)
    }

    // The expected values are literals rather than `GlassChipButtonStyle
    // .pressedOpacity`, so the test pins the actual numbers instead of
    // restating the constant back to itself and passing by construction.
    @Test("the label dims while pressed and is opaque otherwise", arguments: [
        (true, 0.7),
        (false, 1.0),
    ])
    @MainActor
    func labelOpacityTracksPressedState(isPressed: Bool, expected: Double) {
        #expect(GlassChipButtonStyle.labelOpacity(isPressed: isPressed) == expected)
    }

    @Test("pressed dimming is actually a dimming, not a no-op")
    @MainActor
    func pressedOpacityDims() {
        // Guards the whole point of the branch above: a `pressedOpacity` of 1
        // would satisfy it while giving the button no press feedback at all.
        #expect(GlassChipButtonStyle.pressedOpacity < 1)
    }

    @Test(".glassChip resolves to a GlassChipButtonStyle")
    @MainActor
    func glassChipStatic() {
        let style: GlassChipButtonStyle = .glassChip
        #expect(type(of: style) == GlassChipButtonStyle.self)
    }
}
