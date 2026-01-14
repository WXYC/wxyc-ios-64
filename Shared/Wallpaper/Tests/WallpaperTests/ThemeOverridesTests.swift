//
//  ThemeOverridesTests.swift
//  WallpaperTests
//
//  Tests for ThemeOverrides struct.
//

import Testing
import Foundation
@testable import Wallpaper

@Suite("ThemeOverrides")
struct ThemeOverridesTests {

    @Test("isEmpty returns true when all properties are nil")
    func isEmptyWhenAllNil() {
        let overrides = ThemeOverrides()
        #expect(overrides.isEmpty)
    }

    @Test("isEmpty returns false when any property is set")
    func isNotEmptyWhenPropertySet() {
        let withHue = ThemeOverrides(accentHue: 180)
        #expect(!withHue.isEmpty)

        let withSaturation = ThemeOverrides(accentSaturation: 0.5)
        #expect(!withSaturation.isEmpty)

        let withOpacity = ThemeOverrides(overlayOpacity: 0.3)
        #expect(!withOpacity.isEmpty)

        let withBlur = ThemeOverrides(blurRadius: 12.0)
        #expect(!withBlur.isEmpty)

        let withDark = ThemeOverrides(overlayDarkness: 0.0)
        #expect(!withDark.isEmpty)

        let withMin = ThemeOverrides(lcdMinOffset: HSBOffset(hue: 10, saturation: 0, brightness: -0.1))
        #expect(!withMin.isEmpty)

        let withMax = ThemeOverrides(lcdMaxOffset: HSBOffset(hue: 0, saturation: 0.1, brightness: 0))
        #expect(!withMax.isEmpty)
    }

    @Test("reset clears all properties")
    func resetClearsAllProperties() {
        var overrides = ThemeOverrides(
            accentHue: 180,
            accentSaturation: 0.5,
            overlayOpacity: 0.3,
            blurRadius: 12.0,
            overlayDarkness: 0.0,
            lcdMinOffset: HSBOffset(hue: 10, saturation: 0, brightness: -0.1),
            lcdMaxOffset: HSBOffset(hue: 0, saturation: 0.1, brightness: 0)
        )

        #expect(!overrides.isEmpty)

        overrides.reset()

        #expect(overrides.isEmpty)
        #expect(overrides.accentHue == nil)
        #expect(overrides.accentSaturation == nil)
        #expect(overrides.overlayOpacity == nil)
        #expect(overrides.blurRadius == nil)
        #expect(overrides.overlayDarkness == nil)
        #expect(overrides.lcdMinOffset == nil)
        #expect(overrides.lcdMaxOffset == nil)
    }

    @Test("Equatable conformance works correctly")
    func equatableConformance() {
        let a = ThemeOverrides(accentHue: 180, accentSaturation: 0.5)
        let b = ThemeOverrides(accentHue: 180, accentSaturation: 0.5)
        let c = ThemeOverrides(accentHue: 200, accentSaturation: 0.5)

        #expect(a == b)
        #expect(a != c)
    }

    @Test("Codable roundtrip preserves values")
    func codableRoundtrip() throws {
        let original = ThemeOverrides(
            accentHue: 180,
            accentSaturation: 0.5,
            overlayOpacity: 0.3,
            blurRadius: 12.0,
            overlayDarkness: 0.25,
            lcdMinOffset: HSBOffset(hue: 10, saturation: 0, brightness: -0.1),
            lcdMaxOffset: HSBOffset(hue: 0, saturation: 0.1, brightness: 0)
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ThemeOverrides.self, from: data)

        #expect(decoded == original)
    }

    @Test("Codable handles nil values")
    func codableHandlesNilValues() throws {
        let original = ThemeOverrides(accentHue: 180)

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ThemeOverrides.self, from: data)

        #expect(decoded.accentHue == 180)
        #expect(decoded.accentSaturation == nil)
        #expect(decoded.overlayOpacity == nil)
    }
}
