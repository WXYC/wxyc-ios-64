//
//  HandleGlyphMetricsTests.swift
//  WXUI
//
//  Verifies the per-character advance widths used to render the on-air handle's
//  grade wave letter-by-letter. The advances fold kerning in — summing them
//  reproduces the laid-out line width — so a row of per-letter views pinned to
//  them matches the width of the single laid-out string, and the wave doesn't
//  make the handle breathe wider while it plays.
//
//  Created by Jake Bromberg on 07/30/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import CoreText
import CoreGraphics
@testable import WXUI

@Suite("Handle glyph metrics")
struct HandleGlyphMetricsTests {

    /// A concrete font to measure against. Helvetica ships everywhere the tests
    /// run and has real kerning pairs, so the sum-vs-line-width invariant is a
    /// genuine check rather than a tautology.
    private let font = CTFontCreateWithName("Helvetica" as CFString, 24, nil)

    private func lineWidth(_ string: String) -> CGFloat {
        let attributed = NSAttributedString(
            string: string,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
        )
        return CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed), nil, nil, nil))
    }

    @Test("There is one advance per character")
    func oneAdvancePerCharacter() throws {
        let string = "DJ HOUNDSTOOTH"
        let advances = try #require(handleCharacterAdvances(for: string, font: font))
        #expect(advances.count == string.count)
    }

    @Test("The advances sum to the laid-out line width, kerning included")
    func advancesSumToLineWidth() throws {
        // "AV" and "To" are classic negative-kern pairs; a naive per-glyph advance
        // sum would overshoot the real line, so matching it proves kerning is folded in.
        for string in ["DJ HOUNDSTOOTH", "AVATAR", "TOTO", "WXYC"] {
            let advances = try #require(handleCharacterAdvances(for: string, font: font))
            let sum = advances.reduce(0, +)
            #expect(abs(sum - lineWidth(string)) < 0.5)
        }
    }

    @Test("Every advance is non-negative")
    func advancesNonNegative() throws {
        let advances = try #require(handleCharacterAdvances(for: "AVATAR", font: font))
        #expect(advances.allSatisfy { $0 >= 0 })
    }

    @Test("An empty string has no advances")
    func emptyString() {
        #expect(handleCharacterAdvances(for: "", font: font) == [])
    }
}
