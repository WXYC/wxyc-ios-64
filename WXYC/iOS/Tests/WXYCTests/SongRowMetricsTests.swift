//
//  SongRowMetricsTests.swift
//  WXYC
//
//  Pins the sizing `SongRowPanel` and `RowArtworkSlot` share: the 2.5 aspect
//  ratio, the artwork slot at 1/2.5 of the row width, and 12pt of padding.
//
//  Created by Jake Bromberg on 10/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import CoreGraphics
import Testing
@testable import WXYC

@Suite("SongRowMetrics")
struct SongRowMetricsTests {
    @Test("The artwork slot is a 2.5th of the row width", arguments: [
        (250 as CGFloat, 100 as CGFloat),
        (358, 143.2),
        (400, 160),
        (600, 240),
    ])
    func artworkSlotWidth(rowWidth: CGFloat, expected: CGFloat) {
        #expect(abs(SongRowMetrics.artworkSlotWidth(rowWidth: rowWidth) - expected) < 0.001)
    }

    @Test("The artwork side is the slot width less padding on both sides, never negative", arguments: [
        (250 as CGFloat, 76 as CGFloat),
        (400, 136),
        (600, 216),
        (50, 0),
        (0, 0),
    ])
    func artworkSide(rowWidth: CGFloat, expected: CGFloat) {
        #expect(abs(SongRowMetrics.artworkSide(rowWidth: rowWidth) - expected) < 0.001)
    }

    @Test("The row aspect ratio and artwork padding are the playcut row's")
    func constants() {
        #expect(SongRowMetrics.aspectRatio == 2.5)
        #expect(SongRowMetrics.artworkPadding == 12)
        #expect(SongRowMetrics.cornerRadius == 12)
        #expect(SongRowMetrics.shadowOffsetAtTop == -3)
        #expect(SongRowMetrics.shadowOffsetAtBottom == 3)
    }
}

@Suite("SpecialtyCardLayout")
struct SpecialtyCardLayoutTests {
    @Test("The slot is the playcut row's slot and the text takes the rest, at any card width", arguments: [
        (250 as CGFloat, 100 as CGFloat, 150 as CGFloat),
        (378, 151.2, 226.8),
        (576, 230.4, 345.6),
        (0, 0, 0),
    ])
    func columnWidths(width: CGFloat, slot: CGFloat, text: CGFloat) {
        let columns = SpecialtyCardLayout.columnWidths(forCardWidth: width)
        #expect(abs(columns.slot - slot) < 0.001)
        #expect(abs(columns.text - text) < 0.001)
        #expect(abs(columns.slot - 2 * SongRowMetrics.artworkPadding - SongRowMetrics.artworkSide(rowWidth: width)) < 0.001
            || SongRowMetrics.artworkSide(rowWidth: width) == 0)
    }

    @Test("Card height is the taller of the slot and the text", arguments: [
        (400 as CGFloat, 50 as CGFloat), (400, 300), (400, 160),
    ])
    func cardHeight(width: CGFloat, text: CGFloat) {
        let slot = SpecialtyCardLayout.columnWidths(forCardWidth: width).slot
        #expect(abs(SpecialtyCardLayout.cardHeight(forCardWidth: width, textHeight: text) - max(slot, text)) < 0.001)
    }

    @Test("A child is centered vertically in the card, and sits at the top when it fills or overflows it", arguments: [
        (160 as CGFloat, 100 as CGFloat, 30 as CGFloat),
        (160, 160, 0),
        (160, 200, 0),
        (0, 0, 0),
    ])
    func centeredOffset(cardHeight: CGFloat, childHeight: CGFloat, expected: CGFloat) {
        #expect(abs(SpecialtyCardLayout.centeredOffset(cardHeight: cardHeight, childHeight: childHeight) - expected) < 0.001)
    }

    @Test("Resolved width falls back for nil and infinite proposals", arguments: [
        (nil, 600), (CGFloat.infinity, 600), (320, 320),
    ] as [(CGFloat?, CGFloat)])
    func resolvedWidth(proposed: CGFloat?, expected: CGFloat) {
        #expect(SpecialtyCardLayout.resolvedWidth(proposed) == expected)
        #expect(SpecialtyCardLayout.columnWidths(forCardWidth: SpecialtyCardLayout.resolvedWidth(proposed)).text.isFinite)
    }
}
