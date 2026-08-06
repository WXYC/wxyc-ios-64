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

    @Test(".glassChip resolves to a GlassChipButtonStyle")
    @MainActor
    func glassChipStatic() {
        let style: GlassChipButtonStyle = .glassChip
        #expect(type(of: style) == GlassChipButtonStyle.self)
    }
}
