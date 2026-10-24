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
