//
//  HandleWaveAxesTests.swift
//  Playlist
//
//  Verifies the on-air handle wave's presentation math that the banner view drives
//  per letter and per frame: mapping a crest intensity onto the SF Pro grade and
//  weight axes, and turning elapsed time into a clamped animation progress.
//
//  Created by Jake Bromberg on 07/30/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Playlist

@Suite("Handle wave presentation")
struct HandleWaveAxesTests {

    // MARK: - Axis mapping

    @Test("At rest (intensity 0) both axes sit at their resting values")
    func axesRestAtZeroIntensity() {
        let axes = HandleWaveAxes(restingGrade: 936, gradeDepth: 536, restingWeight: 648, weightDepth: 647)
        #expect(axes.grade(atIntensity: 0) == 936)
        #expect(axes.weight(atIntensity: 0) == 648)
    }

    @Test("At full intensity each axis reaches its resting value minus its depth")
    func axesReachFullDipAtOne() {
        let axes = HandleWaveAxes(restingGrade: 936, gradeDepth: 536, restingWeight: 648, weightDepth: 647)
        #expect(axes.grade(atIntensity: 1) == 936 - 536)  // 400 — the grade floor
        #expect(axes.weight(atIntensity: 1) == 648 - 647) // 1 — the weight floor
    }

    @Test("Each axis dips linearly with intensity")
    func axesAreLinear() {
        let axes = HandleWaveAxes(restingGrade: 900, gradeDepth: 400, restingWeight: 600, weightDepth: 500)
        #expect(abs(axes.grade(atIntensity: 0.5) - (900 - 200)) < 0.0001)
        #expect(abs(axes.weight(atIntensity: 0.25) - (600 - 125)) < 0.0001)
    }

    @Test("A zero depth leaves that axis at rest for any intensity, independent of the other")
    func zeroDepthAxisIsInert() {
        let axes = HandleWaveAxes(restingGrade: 936, gradeDepth: 0, restingWeight: 648, weightDepth: 647)
        for step in 0...10 {
            #expect(axes.grade(atIntensity: Double(step) / 10) == 936)
        }
        // The weight axis still dips even though grade is inert.
        #expect(axes.weight(atIntensity: 1) == 1)
    }

    // MARK: - Progress / timing

    @Test("Progress runs 0 at the start to 1 at the end, linearly")
    func progressSpansZeroToOne() {
        #expect(handleWaveProgress(elapsed: 0, totalDuration: 2) == 0)
        #expect(handleWaveProgress(elapsed: 1, totalDuration: 2) == 0.5)
        #expect(handleWaveProgress(elapsed: 2, totalDuration: 2) == 1)
    }

    @Test("Progress clamps out-of-range elapsed times to the endpoints")
    func progressClamps() {
        #expect(handleWaveProgress(elapsed: -1, totalDuration: 2) == 0)
        #expect(handleWaveProgress(elapsed: 5, totalDuration: 2) == 1)
    }

    @Test("A non-positive total duration yields the resting frame (progress 1)")
    func progressRestsWhenNoDuration() {
        #expect(handleWaveProgress(elapsed: 0, totalDuration: 0) == 1)
        #expect(handleWaveProgress(elapsed: 1, totalDuration: -3) == 1)
    }
}
