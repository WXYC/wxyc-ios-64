//
//  ContentColumnTests.swift
//  WXYC
//
//  Pins the pure width policy behind `ContentColumn`: narrower containers pass
//  through untouched, wider ones clamp to the 600pt cap, and the cap stays above
//  the 440pt iPhone reference so the LCD split and two-column work can engage.
//
//  Created by Jake Bromberg on 10/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import CoreGraphics
import Testing
@testable import WXYC

@Suite("ContentColumn")
struct ContentColumnTests {
    @Test("Effective width passes through below the cap and clamps above it", arguments: [
        (320 as CGFloat, 320 as CGFloat),
        (440, 440),
        (600, 600),
        (834, 600),
        (1440, 600),
    ])
    func effectiveWidth(available: CGFloat, expected: CGFloat) {
        #expect(ContentColumn.effectiveWidth(available: available) == expected)
    }

    @Test("The cap is 600pt and exceeds the 440pt phone reference width")
    func capExceedsReference() {
        #expect(ContentColumn.maxWidth == 600)
        #expect(ContentColumn.referenceWidth == 440)
        #expect(ContentColumn.maxWidth > ContentColumn.referenceWidth)
    }
}
