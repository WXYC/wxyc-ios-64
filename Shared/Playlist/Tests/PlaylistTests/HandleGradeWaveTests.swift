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

    @Test("With multiple repetitions the handle rests at the global ends and every sweep boundary")
    func repetitionsRestAtBoundaries() {
        let repetitions = 4
        let wave = HandleGradeWave(baseGrade: base, depth: 300, crestHalfWidth: 0.3, repetitions: repetitions)
        let count = 8
        // Progress k/repetitions is the seam between sweep k and k+1 (and the two
        // global endpoints); the crest is off the string there, so all letters rest.
        for boundary in 0...repetitions {
            let progress = Double(boundary) / Double(repetitions)
            for index in 0..<count {
                #expect(abs(wave.grade(characterIndex: index, count: count, progress: progress) - base) < 0.0001)
            }
        }
    }

    @Test("Each repetition is a full left-to-right sweep of the crest")
    func repetitionsSweepEachPass() {
        let repetitions = 3
        let wave = HandleGradeWave(baseGrade: base, depth: 300, crestHalfWidth: 0.2, repetitions: repetitions)
        let count = 20

        func mostLightenedIndex(at progress: Double) -> Int {
            (0..<count).min { lhs, rhs in
                wave.grade(characterIndex: lhs, count: count, progress: progress)
                    < wave.grade(characterIndex: rhs, count: count, progress: progress)
            }!
        }

        // Sampling early vs. late within each individual sweep shows the crest
        // advancing left to right on every pass, not just the first.
        for sweep in 0..<repetitions {
            let start = Double(sweep) / Double(repetitions)
            let early = start + 0.15 / Double(repetitions)
            let late = start + 0.85 / Double(repetitions)
            #expect(mostLightenedIndex(at: early) < mostLightenedIndex(at: late))
        }
    }

    @Test("A non-positive repetition count is handled defensively as a single sweep")
    func repetitionsDefensive() {
        let count = 8
        let single = HandleGradeWave(baseGrade: base, depth: 300, crestHalfWidth: 0.3, repetitions: 1)
        let zero = HandleGradeWave(baseGrade: base, depth: 300, crestHalfWidth: 0.3, repetitions: 0)
        for step in 0...20 {
            let progress = Double(step) / 20
            for index in 0..<count {
                #expect(zero.grade(characterIndex: index, count: count, progress: progress)
                    == single.grade(characterIndex: index, count: count, progress: progress))
            }
        }
    }

    // MARK: - Spacing / overlap

    /// The number of contiguous runs of lit (below-base) letters at an instant —
    /// one per crest currently on the string.
    private func litRunCount(_ wave: HandleGradeWave, count: Int, progress: Double) -> Int {
        var runs = 0
        var inRun = false
        for index in 0..<count {
            let lit = wave.grade(characterIndex: index, count: count, progress: progress) < base - 0.5
            if lit && !inRun { runs += 1 }
            inRun = lit
        }
        return runs
    }

    @Test("Spacing 1 keeps the sweeps sequential — never two crests on the string at once")
    func spacingOneIsSequential() {
        let wave = HandleGradeWave(baseGrade: base, depth: 300, crestHalfWidth: 0.2, repetitions: 4, spacing: 1)
        let count = 24
        for step in 0...80 {
            #expect(litRunCount(wave, count: count, progress: Double(step) / 80) <= 1)
        }
    }

    @Test("Overlapping spacing puts several crests on the string at the same time")
    func overlapProducesSimultaneousCrests() {
        let count = 24
        let sequential = HandleGradeWave(baseGrade: base, depth: 300, crestHalfWidth: 0.15, repetitions: 4, spacing: 1)
        let overlapping = HandleGradeWave(baseGrade: base, depth: 300, crestHalfWidth: 0.15, repetitions: 4, spacing: 0.35)

        func maxSimultaneousRuns(_ wave: HandleGradeWave) -> Int {
            (0...100).map { litRunCount(wave, count: count, progress: Double($0) / 100) }.max() ?? 0
        }
        #expect(maxSimultaneousRuns(sequential) == 1)
        #expect(maxSimultaneousRuns(overlapping) >= 2)
    }

    @Test("The animation rests at both ends for any spacing")
    func spacingRestsAtEnds() {
        let wave = HandleGradeWave(baseGrade: base, depth: 300, crestHalfWidth: 0.3, repetitions: 4, spacing: 0.3)
        let count = 10
        for index in 0..<count {
            #expect(abs(wave.grade(characterIndex: index, count: count, progress: 0) - base) < 0.0001)
            #expect(abs(wave.grade(characterIndex: index, count: count, progress: 1) - base) < 0.0001)
        }
    }

    @Test("Spacing is clamped: an over-range value behaves like the nearest bound")
    func spacingClamped() {
        let count = 16
        let atMax = HandleGradeWave(baseGrade: base, depth: 300, crestHalfWidth: 0.2, repetitions: 3, spacing: 1)
        let overMax = HandleGradeWave(baseGrade: base, depth: 300, crestHalfWidth: 0.2, repetitions: 3, spacing: 2)
        for step in 0...40 {
            let progress = Double(step) / 40
            for index in 0..<count {
                #expect(overMax.grade(characterIndex: index, count: count, progress: progress)
                    == atMax.grade(characterIndex: index, count: count, progress: progress))
            }
        }
    }

    @Test("Normalized span grows by the spacing for each extra repetition")
    func normalizedSpanScales() {
        #expect(HandleGradeWave(baseGrade: base, repetitions: 1, spacing: 0.4).normalizedSpan == 1)
        #expect(abs(HandleGradeWave(baseGrade: base, repetitions: 3, spacing: 1).normalizedSpan - 3) < 0.0001)
        #expect(abs(HandleGradeWave(baseGrade: base, repetitions: 3, spacing: 0.5).normalizedSpan - 2) < 0.0001)
    }

    // MARK: - Intensity (the axis-agnostic shape)

    @Test("Intensity rests at 0 at both ends and peaks at 1 under a crest center")
    func intensityShape() {
        let wave = HandleGradeWave(baseGrade: base, depth: 300, crestHalfWidth: 0.5)
        for index in 0..<6 {
            #expect(wave.intensity(characterIndex: index, count: 6, progress: 0) == 0)
            #expect(wave.intensity(characterIndex: index, count: 6, progress: 1) == 0)
        }
        // Single letter with the crest dead-center at progress 0.25 → full intensity.
        #expect(abs(wave.intensity(characterIndex: 0, count: 1, progress: 0.25) - 1) < 0.0001)
    }

    @Test("Intensity stays within 0...1 for any letter, progress, and spacing")
    func intensityBounds() {
        let wave = HandleGradeWave(baseGrade: base, depth: 300, crestHalfWidth: 0.25, repetitions: 4, spacing: 0.3)
        let count = 18
        for step in 0...60 {
            let progress = Double(step) / 60
            for index in 0..<count {
                let intensity = wave.intensity(characterIndex: index, count: count, progress: progress)
                #expect(intensity >= 0)
                #expect(intensity <= 1 + 0.0001)
            }
        }
    }

    @Test("Grade is the base lightened by depth in proportion to intensity")
    func gradeTracksIntensity() {
        let wave = HandleGradeWave(baseGrade: base, depth: 420, crestHalfWidth: 0.3, repetitions: 3, spacing: 0.4)
        let count = 14
        for step in 0...30 {
            let progress = Double(step) / 30
            for index in 0..<count {
                let intensity = wave.intensity(characterIndex: index, count: count, progress: progress)
                let grade = wave.grade(characterIndex: index, count: count, progress: progress)
                #expect(abs(grade - (base - 420 * intensity)) < 0.0001)
            }
        }
    }
}
