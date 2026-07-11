//
//  DashedLineTests.swift
//  WXYC
//
//  Verifies the ticket perforation's dashing rules: every dash and gap is the
//  same length, and the line begins and ends with a gap, at any width.
//
//  Created by Jake Bromberg on 07/10/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import SwiftUI
@testable import WXYC

@Suite("DashedLine")
struct DashedLineTests {
    private let tolerance: CGFloat = 0.0001

    /// The painted dashes, as `(start, end)` x-coordinates, extracted from the
    /// shape's path for a rect of the given width.
    private func dashes(width: CGFloat, approximateSegment: CGFloat = 4) -> [(start: CGFloat, end: CGFloat)] {
        let path = DashedLine(approximateSegment: approximateSegment)
            .path(in: CGRect(x: 0, y: 0, width: width, height: 2))
        var result: [(start: CGFloat, end: CGFloat)] = []
        var pendingStart: CGFloat?
        path.forEach { element in
            switch element {
            case .move(let point):
                pendingStart = point.x
            case .line(let point):
                if let start = pendingStart {
                    result.append((start: start, end: point.x))
                    pendingStart = nil
                }
            default:
                break
            }
        }
        return result
    }

    @Test("Every dash and gap is the same length")
    func equalSegments() {
        let dashes = dashes(width: 200)
        try? #require(dashes.count >= 2)
        let segment = dashes[0].end - dashes[0].start

        for dash in dashes {
            #expect(abs((dash.end - dash.start) - segment) < tolerance)
        }
        for i in 1..<dashes.count {
            let gap = dashes[i].start - dashes[i - 1].end
            #expect(abs(gap - segment) < tolerance)
        }
    }

    @Test("The line begins and ends with a gap")
    func gapsAtBothEnds() {
        let width: CGFloat = 200
        let dashes = dashes(width: width)
        let segment = dashes[0].end - dashes[0].start

        // Leading gap: the first dash starts one segment in, not flush at the edge.
        #expect(abs(dashes[0].start - segment) < tolerance)
        // Trailing gap: the last dash ends one segment before the far edge.
        #expect(abs((width - dashes.last!.end) - segment) < tolerance)
    }

    @Test("Dashing stays proportional across widths", arguments: [80.0, 200.0, 641.0] as [CGFloat])
    func proportional(width: CGFloat) {
        let dashes = dashes(width: width)
        let segment = dashes[0].end - dashes[0].start

        // An odd number of equal segments — dashes + one extra gap — spans the
        // width exactly, so the dashing scales with the line rather than leaving a
        // ragged remainder.
        let totalSegments = 2 * dashes.count + 1
        #expect(abs(CGFloat(totalSegments) * segment - width) < tolerance)
        // The snapped length stays near the requested target.
        #expect(abs(segment - 4) < 2)
    }
}
