//
//  WidthAxisFitter.swift
//  Playlist
//
//  Solves for the SF Pro width (`wdth`) axis value that condenses the on-air DJ
//  handle onto one line beside the say-hi chip, without shrinking the point
//  size. The handle ships fully expanded (width 150), so most "condensing" just
//  spends that expansion back toward standard width at no legibility cost; only
//  a genuinely long handle dips into the designed condensed widths. The solver
//  is measurement-agnostic — it takes a closure returning the rendered line
//  width at a candidate axis — so it's unit-tested without a font or a device.
//
//  Created by Jake Bromberg on 07/19/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import CoreGraphics

/// Returns the largest width-axis value in `[floor, baseAxis]` at which the
/// handle fits within `availableWidth` on one line, or the floor when even that
/// is too narrow (the caller then allows a wrap).
///
/// - Parameters:
///   - availableWidth: The horizontal space the handle may occupy (the banner
///     row minus the chip and gap).
///   - baseAxis: The default/expanded width axis (the tuned shipping look).
///   - floor: The narrowest width axis that still reads legibly.
///   - measure: Returns the rendered one-line width of the handle at a given
///     width-axis value.
///
/// Width scales close to — but not exactly — linearly with the axis, so the
/// first estimate is proportional and then refined a few times toward the fit.
public func fittedWidthAxis(
    availableWidth: CGFloat,
    baseAxis: Double,
    floor: Double,
    measure: (Double) -> CGFloat
) -> Double {
    let clampedFloor = min(floor, baseAxis)

    let natural = measure(baseAxis)
    guard natural > availableWidth, natural > 0 else { return baseAxis }

    // Proportional first estimate: width ≈ k × axis.
    var axis = min(baseAxis, max(clampedFloor, baseAxis * Double(availableWidth / natural)))

    // Refine: width isn't perfectly linear in the axis, so nudge down until it
    // fits (or we hit the floor). A handful of iterations converges tightly for
    // the near-linear real font.
    for _ in 0..<4 {
        let width = measure(axis)
        guard width > availableWidth, axis > clampedFloor, width > 0 else { break }
        axis = max(clampedFloor, axis * Double(availableWidth / width))
    }

    return axis
}
