//
//  WidthAxisFitterTests.swift
//  Playlist
//
//  Verifies the pure width-axis solver that condenses the on-air DJ handle to
//  fit one line: it returns the base axis when the name already fits, narrows
//  proportionally when it doesn't, clamps to the legibility floor, and never
//  exceeds the base. The solver takes a measurement closure so it's testable
//  with a synthetic width model, no font or device required.
//
//  Created by Jake Bromberg on 07/19/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Playlist

@Suite("WidthAxisFitter Tests")
struct WidthAxisFitterTests {

    /// A linear width model: rendered line width is `k × axis`.
    private func linear(_ k: CGFloat) -> @Sendable (Double) -> CGFloat {
        { CGFloat($0) * k }
    }

    @Test("Returns the base axis when the name already fits")
    func fitsAtBase() {
        // natural width at base = 2 × 150 = 300 ≤ 400
        let axis = fittedWidthAxis(availableWidth: 400, baseAxis: 150, floor: 30, measure: linear(2))
        #expect(axis == 150)
    }

    @Test("Condenses proportionally to fit when too wide")
    func condensesToFit() {
        // natural = 300 > 100 → 150 × (100/300) = 50, which measures to exactly 100
        let axis = fittedWidthAxis(availableWidth: 100, baseAxis: 150, floor: 30, measure: linear(2))
        #expect(abs(axis - 50) < 0.001)
    }

    @Test("Clamps to the floor when even the floor overflows")
    func flooredWhenTooLong() {
        // estimate 150 × (30/300) = 15, clamped up to the floor of 40
        let axis = fittedWidthAxis(availableWidth: 30, baseAxis: 150, floor: 40, measure: linear(2))
        #expect(axis == 40)
    }

    @Test("Never exceeds the base axis")
    func neverExceedsBase() {
        let axis = fittedWidthAxis(availableWidth: 10_000, baseAxis: 150, floor: 30, measure: linear(2))
        #expect(axis == 150)
    }

    @Test("A floor misconfigured above the base clamps to the base")
    func floorAboveBase() {
        let axis = fittedWidthAxis(availableWidth: 1, baseAxis: 100, floor: 130, measure: linear(2))
        #expect(axis == 100)
    }

    @Test("Converges so the fitted axis actually fits (nonlinear model)")
    func convergesNonlinear() {
        // width = 2 × axis + 20 — an affine model (like the real font, width is
        // near-linear in the axis but not exactly proportional), so the first
        // proportional estimate overshoots and the solver refines down to fit.
        let measure: @Sendable (Double) -> CGFloat = { CGFloat($0 * 2 + 20) }
        let axis = fittedWidthAxis(availableWidth: 100, baseAxis: 150, floor: 5, measure: measure)
        #expect(axis >= 5 && axis <= 150)
        #expect(measure(axis) <= 100 + 0.5)
    }
}
