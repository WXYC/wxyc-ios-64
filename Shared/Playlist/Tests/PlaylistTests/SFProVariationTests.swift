//
//  SFProVariationTests.swift
//  Playlist
//
//  Tests for the SF Pro variable-font axis model used by the on-air banner controls.
//
//  Created by Jake Bromberg on 07/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import Playlist

// MARK: - SF Pro Variation Tests

@Suite("SF Pro Variation Tests")
struct SFProVariationTests {

    @Test("Each axis carries its OpenType 4-character tag")
    func axisTags() {
        #expect(SFProFontAxis.weight.tag == "wght")
        #expect(SFProFontAxis.width.tag == "wdth")
        #expect(SFProFontAxis.opticalSize.tag == "opsz")
        #expect(SFProFontAxis.grade.tag == "GRAD")
    }

    @Test("Axis identifiers are the tags packed big-endian into a UInt32")
    func axisIdentifiers() {
        #expect(SFProFontAxis.weight.identifier == 0x7767_6874)
        #expect(SFProFontAxis.width.identifier == 0x7764_7468)
        #expect(SFProFontAxis.opticalSize.identifier == 0x6F70_737A)
        #expect(SFProFontAxis.grade.identifier == 0x4752_4144)
    }

    @Test("identifier(for:) encodes an arbitrary four-character tag")
    func identifierEncoding() {
        #expect(SFProFontAxis.identifier(for: "wght") == 0x7767_6874)
        #expect(SFProFontAxis.identifier(for: "GRAD") == 0x4752_4144)
    }

    @Test("Axis ranges match the SF Pro variation table")
    func axisRanges() {
        #expect(SFProFontAxis.weight.range == 1...1000)
        #expect(SFProFontAxis.width.range == 30...150)
        #expect(SFProFontAxis.opticalSize.range == 17...96)
        #expect(SFProFontAxis.grade.range == 400...1000)
    }

    @Test("Axis defaults match the tuned DJ-handle look")
    func axisDefaults() {
        #expect(SFProFontAxis.weight.defaultValue == 648)
        #expect(SFProFontAxis.width.defaultValue == 150)
        #expect(SFProFontAxis.opticalSize.defaultValue == 17)
        #expect(SFProFontAxis.grade.defaultValue == 936)
    }

    @Test("A default variation uses each axis's default value")
    func defaultVariation() {
        let variation = SFProVariation()
        #expect(variation.weight == SFProFontAxis.weight.defaultValue)
        #expect(variation.width == SFProFontAxis.width.defaultValue)
        #expect(variation.opticalSize == SFProFontAxis.opticalSize.defaultValue)
        #expect(variation.grade == SFProFontAxis.grade.defaultValue)
    }

    @Test("variationDictionary keys each axis identifier to its value")
    func variationDictionaryMapping() {
        let variation = SFProVariation(weight: 860, width: 55, opticalSize: 40, grade: 700)
        let dict = variation.variationDictionary
        #expect(dict[SFProFontAxis.weight.identifier] == 860)
        #expect(dict[SFProFontAxis.width.identifier] == 55)
        #expect(dict[SFProFontAxis.opticalSize.identifier] == 40)
        #expect(dict[SFProFontAxis.grade.identifier] == 700)
    }

    @Test("variationDictionary clamps out-of-range values to the axis bounds")
    func variationDictionaryClamps() {
        let variation = SFProVariation(weight: 5000, width: 0, opticalSize: 200, grade: 100)
        let dict = variation.variationDictionary
        #expect(dict[SFProFontAxis.weight.identifier] == 1000)
        #expect(dict[SFProFontAxis.width.identifier] == 30)
        #expect(dict[SFProFontAxis.opticalSize.identifier] == 96)
        #expect(dict[SFProFontAxis.grade.identifier] == 400)
    }
}
