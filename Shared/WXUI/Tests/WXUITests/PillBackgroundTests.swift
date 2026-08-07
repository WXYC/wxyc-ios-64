//
//  PillBackgroundTests.swift
//  WXUI
//
//  Tests over the pure geometry rule behind `.pillBackground(background:)` — a
//  capsule's corner radius is half its rendered height. The `GeometryReader`
//  itself isn't unit-testable without measuring a live layout pass, so this
//  targets the halving rule the modifier hands to the caller's background
//  closure.
//
//  Created by Jake Bromberg on 08/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import CoreGraphics
import Testing
@testable import WXUI

@Suite("PillBackground")
struct PillBackgroundTests {
    @Test("corner radius is half the rendered height", arguments: [
        (0.0, 0.0),
        (24.0, 12.0),
        (44.0, 22.0),
        (37.0, 18.5),
    ] as [(CGFloat, CGFloat)])
    func cornerRadius(height: CGFloat, expectedRadius: CGFloat) {
        #expect(PillBackgroundGeometry.cornerRadius(forHeight: height) == expectedRadius)
    }
}
