//
//  ColorPaletteCacheKeyTests.swift
//  ColorPalette
//
//  Tests for ColorPaletteCacheKey cache key generation.
//
//  Created by Jake Bromberg on 03/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import ColorPalette

@Suite("ColorPaletteCacheKey Tests")
struct ColorPaletteCacheKeyTests {

    @Test("palette key includes mode and identifier")
    func paletteKeyIncludesModeAndIdentifier() {
        let key = ColorPaletteCacheKey.palette(mode: .triad, identifier: "Stereolab-Aluminum Tunes")
        #expect(key.contains("triad"))
        #expect(key.contains("Stereolab-Aluminum Tunes"))
    }

    @Test("palette key differs for different modes")
    func paletteKeyDiffersForDifferentModes() {
        let triadKey = ColorPaletteCacheKey.palette(mode: .triad, identifier: "Cat Power-Moon Pix")
        let complementaryKey = ColorPaletteCacheKey.palette(mode: .complementary, identifier: "Cat Power-Moon Pix")
        #expect(triadKey != complementaryKey)
    }

    @Test("palette key differs for different identifiers")
    func paletteKeyDiffersForDifferentIdentifiers() {
        let key1 = ColorPaletteCacheKey.palette(mode: .triad, identifier: "Juana Molina-DOGA")
        let key2 = ColorPaletteCacheKey.palette(mode: .triad, identifier: "Jessica Pratt-On Your Own Love Again")
        #expect(key1 != key2)
    }

    @Test("palette key is consistent for same inputs")
    func paletteKeyIsConsistentForSameInputs() {
        let key1 = ColorPaletteCacheKey.palette(mode: .square, identifier: "Sessa-Pequena Vertigem de Amor")
        let key2 = ColorPaletteCacheKey.palette(mode: .square, identifier: "Sessa-Pequena Vertigem de Amor")
        #expect(key1 == key2)
    }
}
