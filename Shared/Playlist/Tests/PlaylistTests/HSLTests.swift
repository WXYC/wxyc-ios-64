//
//  HSLTests.swift
//  Playlist
//
//  Tests for the HSL -> RGB conversion used by the on-air banner theme controls.
//
//  Created by Jake Bromberg on 07/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Playlist

// MARK: - HSL Tests

@Suite("HSL Tests")
struct HSLTests {

    /// Compares two RGB tuples within a small tolerance.
    private func expectRGB(
        _ actual: (red: Double, green: Double, blue: Double),
        _ expected: (red: Double, green: Double, blue: Double),
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(abs(actual.red - expected.red) < 0.0001, sourceLocation: sourceLocation)
        #expect(abs(actual.green - expected.green) < 0.0001, sourceLocation: sourceLocation)
        #expect(abs(actual.blue - expected.blue) < 0.0001, sourceLocation: sourceLocation)
    }

    @Test("Zero lightness is black regardless of hue and saturation")
    func blackAtZeroLightness() {
        expectRGB(HSL(hue: 0.4, saturation: 0.8, lightness: 0).rgb, (0, 0, 0))
    }

    @Test("Full lightness is white regardless of hue and saturation")
    func whiteAtFullLightness() {
        expectRGB(HSL(hue: 0.4, saturation: 0.8, lightness: 1).rgb, (1, 1, 1))
    }

    @Test("Zero saturation is a neutral gray at the given lightness")
    func grayWhenDesaturated() {
        expectRGB(HSL(hue: 0.7, saturation: 0, lightness: 0.5).rgb, (0.5, 0.5, 0.5))
    }

    @Test("Hue 0 fully saturated at mid lightness is pure red")
    func pureRed() {
        expectRGB(HSL(hue: 0, saturation: 1, lightness: 0.5).rgb, (1, 0, 0))
    }

    @Test("Hue 1/3 fully saturated at mid lightness is pure green")
    func pureGreen() {
        expectRGB(HSL(hue: 1.0 / 3.0, saturation: 1, lightness: 0.5).rgb, (0, 1, 0))
    }

    @Test("Hue 2/3 fully saturated at mid lightness is pure blue")
    func pureBlue() {
        expectRGB(HSL(hue: 2.0 / 3.0, saturation: 1, lightness: 0.5).rgb, (0, 0, 1))
    }

    @Test("Hue 1/6 fully saturated at mid lightness is pure yellow")
    func pureYellow() {
        expectRGB(HSL(hue: 1.0 / 6.0, saturation: 1, lightness: 0.5).rgb, (1, 1, 0))
    }
}
