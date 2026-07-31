//
//  PerLetterHandleGateTests.swift
//  Playlist
//
//  Verifies the pure gate that decides whether the on-air handle renders as the
//  rigid per-letter row or the flexible single `Text`. The crux is the startup
//  case: the per-letter row can't wrap or compress, so it must wait for the
//  adaptive width to resolve — until then (a zero available width on the first
//  layout pass) the handle falls back to the single `Text`, which won't overflow
//  beside the say-hi chip.
//
//  Created by Jake Bromberg on 07/30/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import CoreGraphics
@testable import Playlist

@Suite("Per-letter handle gate")
struct PerLetterHandleGateTests {

    @Test("Renders per-letter once the adaptive width has resolved")
    func perLetterWhenResolved() {
        #expect(shouldRenderPerLetterHandle(
            waveEnabled: true,
            shapesOneGlyphPerCharacter: true,
            adaptiveWidth: true,
            availableWidth: 320
        ))
    }

    @Test("Falls back to the single Text on the first, unmeasured layout pass")
    func singleTextWhileWidthUnresolved() {
        // The regression: at app start the available width is still zero, so the
        // fitted width isn't known and the rigid row would render at the unfitted
        // base (expanded) width and overflow for a frame. The single `Text` must
        // cover this frame instead.
        #expect(!shouldRenderPerLetterHandle(
            waveEnabled: true,
            shapesOneGlyphPerCharacter: true,
            adaptiveWidth: true,
            availableWidth: 0
        ))
    }

    @Test("Renders per-letter immediately when the adaptive fit is off")
    func perLetterWhenAdaptiveOff() {
        // With adaptive fitting off, the base width is the final width, so there
        // is nothing to wait for even at a zero available width.
        #expect(shouldRenderPerLetterHandle(
            waveEnabled: true,
            shapesOneGlyphPerCharacter: true,
            adaptiveWidth: false,
            availableWidth: 0
        ))
    }

    @Test("Never renders per-letter when the wave is disabled")
    func singleTextWhenWaveDisabled() {
        #expect(!shouldRenderPerLetterHandle(
            waveEnabled: false,
            shapesOneGlyphPerCharacter: true,
            adaptiveWidth: true,
            availableWidth: 320
        ))
    }

    @Test("Never renders per-letter when the handle doesn't shape one glyph per character")
    func singleTextWhenNotOneToOne() {
        // A ligature, combining mark, or surrogate pair can't be pinned to
        // per-character cells, so the handle stays a single `Text`.
        #expect(!shouldRenderPerLetterHandle(
            waveEnabled: true,
            shapesOneGlyphPerCharacter: false,
            adaptiveWidth: true,
            availableWidth: 320
        ))
    }
}
