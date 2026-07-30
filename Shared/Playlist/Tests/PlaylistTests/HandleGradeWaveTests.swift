//
//  HandleGradeWaveTests.swift
//  Playlist
//
//  Verifies the pure, one-shot grade "wave" that sweeps a lightening crest across
//  the on-air DJ handle's letters. The wave modulates only SF Pro's grade (GRAD)
//  axis — which is metric-neutral — so the handle's total width is unchanged, and
//  every letter rests at the base grade at progress 0 and 1 (it plays exactly once).
//
//  Created by Jake Bromberg on 07/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Playlist

@Suite("HandleGradeWave Tests")
struct HandleGradeWaveTests {

    private let base = SFProFontAxis.grade.defaultValue // 936

    @Test("At rest (progress 0 and 1) every letter holds the base grade")
    func restsAtBase() {
        let wave = HandleGradeWave(baseGrade: base, depth: 300, crestHalfWidth: 0.35)
        let count = 8
        for index in 0..<count {
            #expect(wave.grade(characterIndex: index, count: count, progress: 0) == base)
            #expect(wave.grade(characterIndex: index, count: count, progress: 1) == base)
        }
    }

    @Test("The letter under the crest center is lightened by the full depth")
    func crestReachesFullDepth() {
        // Single letter at position 0; with a half-width of 0.5 the crest center
        // reaches 0 at progress = hw / (1 + 2·hw) = 0.5 / 2 = 0.25.
        let wave = HandleGradeWave(baseGrade: base, depth: 300, crestHalfWidth: 0.5)
        let grade = wave.grade(characterIndex: 0, count: 1, progress: 0.25)
        #expect(abs(grade - (base - 300)) < 0.0001)
    }

    @Test("Grade stays within [base − depth, base] for any letter and progress")
    func staysWithinBounds() {
        let depth = 300.0
        let wave = HandleGradeWave(baseGrade: base, depth: depth, crestHalfWidth: 0.35)
        let count = 12
        for step in 0...40 {
            let progress = Double(step) / 40
            for index in 0..<count {
                let grade = wave.grade(characterIndex: index, count: count, progress: progress)
                #expect(grade <= base + 0.0001)
                #expect(grade >= base - depth - 0.0001)
            }
        }
    }

    @Test("Progress is clamped: out-of-range values behave like the endpoints")
    func clampsProgress() {
        let wave = HandleGradeWave(baseGrade: base, depth: 300, crestHalfWidth: 0.35)
        #expect(wave.grade(characterIndex: 3, count: 8, progress: -1) == base)
        #expect(wave.grade(characterIndex: 3, count: 8, progress: 2) == base)
    }

    @Test("A non-positive count is handled defensively and returns the base grade")
    func defensiveCount() {
        let wave = HandleGradeWave(baseGrade: base, depth: 300, crestHalfWidth: 0.35)
        #expect(wave.grade(characterIndex: 0, count: 0, progress: 0.5) == base)
    }

    @Test("The crest travels left to right as progress advances")
    func crestTravels() {
        // The most-lightened letter early in the animation should sit to the left
        // of the most-lightened letter later in the animation.
        let wave = HandleGradeWave(baseGrade: base, depth: 300, crestHalfWidth: 0.25)
        let count = 20

        func mostLightenedIndex(at progress: Double) -> Int {
            (0..<count).min { lhs, rhs in
                wave.grade(characterIndex: lhs, count: count, progress: progress)
                    < wave.grade(characterIndex: rhs, count: count, progress: progress)
            }!
        }

        #expect(mostLightenedIndex(at: 0.3) < mostLightenedIndex(at: 0.7))
    }

    @Test("Zero depth is a no-op — the handle never leaves its base grade")
    func zeroDepthIsInert() {
        let wave = HandleGradeWave(baseGrade: base, depth: 0, crestHalfWidth: 0.35)
        for step in 0...10 {
            #expect(wave.grade(characterIndex: 2, count: 6, progress: Double(step) / 10) == base)
        }
    }
}
