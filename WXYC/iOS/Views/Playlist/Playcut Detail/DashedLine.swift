//
//  DashedLine.swift
//  WXYC
//
//  The perforated tear line drawn along a ticket's seam. Unlike a plain
//  `StrokeStyle(dash:)`, this shape sizes its own dashes so they stay
//  proportional to the line's width: it fills the width with an odd number of
//  equal-length segments and paints every other one. So the dashes and the gaps
//  between them are all one length, and the line both begins and ends with a gap
//  rather than a half-dash butting against a corner notch. Draw it with a plain,
//  non-dashed stroke.
//
//  Created by Jake Bromberg on 07/10/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI

/// A horizontal dashed line, centered vertically in its rect, whose dashes and
/// gaps are all equal in length and which starts and ends on a gap. See the file
/// header for why the dashing is baked into the shape rather than the stroke.
struct DashedLine: Shape {
    /// The nominal dash/gap length. The drawn length is snapped to whatever makes
    /// a whole, odd number of equal segments span the width exactly, so this is a
    /// target the result rounds toward rather than an exact size.
    var approximateSegment: CGFloat = 4

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard rect.width > 0, approximateSegment > 0 else { return path }

        // An odd segment count puts a gap at both ends: gaps sit at the even
        // indices (0, 2, …), dashes at the odd ones, and the final index — being
        // even when the count is odd — is a gap.
        var count = Int((rect.width / approximateSegment).rounded())
        count = max(3, count)
        if count.isMultiple(of: 2) { count += 1 }

        let segment = rect.width / CGFloat(count)
        var index = 1
        while index < count {
            let startX = rect.minX + CGFloat(index) * segment
            path.move(to: CGPoint(x: startX, y: rect.midY))
            path.addLine(to: CGPoint(x: startX + segment, y: rect.midY))
            index += 2
        }
        return path
    }
}
