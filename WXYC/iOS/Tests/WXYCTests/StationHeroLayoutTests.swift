//
//  StationHeroLayoutTests.swift
//  WXYC
//
//  Tests for the width rule that sizes the Station hero's logo.
//
//  Created by Jake Bromberg on 10/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import CoreGraphics
import Testing
@testable import WXYC

@Suite("StationHeroLayout")
struct StationHeroLayoutTests {

    @Test("logo takes a fixed share of the column and is capped on wide windows", arguments: [
        (CGFloat(320), CGFloat(272)),
        (CGFloat(390), CGFloat(331.5)),
        (CGFloat(600), CGFloat(StationHeroLayout.maxLogoWidth)),
        (CGFloat(1400), CGFloat(StationHeroLayout.maxLogoWidth)),
    ])
    func logoWidth(available: CGFloat, expected: CGFloat) {
        #expect(StationHeroLayout.logoWidth(in: available) == expected)
    }
}
