//
//  HandleGradeWaveTests.swift
//  Playlist
//
//  Verifies the pure, one-shot "wave" that sweeps a train of lightening crests
//  across the on-air DJ handle's letters. The model reports a per-letter intensity
//  (0...1) that the view maps onto SF Pro axes; every letter rests at intensity 0
//  at progress 0 and 1, so the animation plays exactly once and the handle starts
//  and ends at its normal look.
//
//  Created by Jake Bromberg on 07/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Playlist

@Suite("HandleGradeWave Tests")
struct HandleGradeWaveTests {

    // MARK: - Crest shape

    @Test("Intensity rests at 0 at both ends and peaks at 1 under a crest center")
    func intensityShape() {
        let wave = HandleGradeWave(crestHalfWidth: 0.5)
        for index in 0..<6 {
            #expect(wave.intensity(characterIndex: index, count: 6, progress: 0) == 0)
            #expect(wave.intensity(characterIndex: index, count: 6, progress: 1) == 0)
        }
        // Single letter with the crest dead-center at progress 0.25 → full intensity.
        #expect(abs(wave.intensity(characterIndex: 0, count: 1, progress: 0.25) - 1) < 0.0001)
    }

    @Test("Intensity stays within 0...1 for any letter, progress, and spacing")
    func intensityBounds() {
        let wave = HandleGradeWave(crestHalfWidth: 0.25, repetitions: 4, spacing: 0.3)
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

    @Test("Progress is clamped: out-of-range values behave like the endpoints (intensity 0)")
    func clampsProgress() {
        let wave = HandleGradeWave(crestHalfWidth: 0.35)
        #expect(wave.intensity(characterIndex: 3, count: 8, progress: -1) == 0)
        #expect(wave.intensity(characterIndex: 3, count: 8, progress: 2) == 0)
    }

    @Test("A non-positive count is handled defensively and returns intensity 0")
    func defensiveCount() {
        let wave = HandleGradeWave(crestHalfWidth: 0.35)
        #expect(wave.intensity(characterIndex: 0, count: 0, progress: 0.5) == 0)
    }

    @Test("The crest travels left to right as progress advances")
    func crestTravels() {
        let wave = HandleGradeWave(crestHalfWidth: 0.25)
        let count = 20
        #expect(mostIntenseIndex(wave, count: count, at: 0.3) < mostIntenseIndex(wave, count: count, at: 0.7))
    }

    // MARK: - Repetitions

    @Test("With multiple repetitions the string rests at the global ends and every sweep boundary")
    func repetitionsRestAtBoundaries() {
        let repetitions = 4
        let wave = HandleGradeWave(crestHalfWidth: 0.3, repetitions: repetitions)
        let count = 8
        // Progress k/repetitions is the seam between sweep k and k+1 (and the two
        // global endpoints); no crest is mid-sweep there, so all letters rest.
        for boundary in 0...repetitions {
            let progress = Double(boundary) / Double(repetitions)
            for index in 0..<count {
                #expect(wave.intensity(characterIndex: index, count: count, progress: progress) < 0.0001)
            }
        }
    }

    @Test("Each repetition is a full left-to-right sweep of the crest")
    func repetitionsSweepEachPass() {
        let repetitions = 3
        let wave = HandleGradeWave(crestHalfWidth: 0.2, repetitions: repetitions)
        let count = 20
        // Sampling early vs. late within each individual sweep shows the crest
        // advancing left to right on every pass, not just the first.
        for sweep in 0..<repetitions {
            let start = Double(sweep) / Double(repetitions)
            let early = start + 0.15 / Double(repetitions)
            let late = start + 0.85 / Double(repetitions)
            #expect(mostIntenseIndex(wave, count: count, at: early) < mostIntenseIndex(wave, count: count, at: late))
        }
    }

    @Test("A non-positive repetition count is handled defensively as a single sweep")
    func repetitionsDefensive() {
        let count = 8
        let single = HandleGradeWave(crestHalfWidth: 0.3, repetitions: 1)
        let zero = HandleGradeWave(crestHalfWidth: 0.3, repetitions: 0)
        for step in 0...20 {
            let progress = Double(step) / 20
            for index in 0..<count {
                #expect(zero.intensity(characterIndex: index, count: count, progress: progress)
                    == single.intensity(characterIndex: index, count: count, progress: progress))
            }
        }
    }

    // MARK: - Spacing / overlap

    @Test("Spacing 1 keeps the sweeps sequential — never two crests on the string at once")
    func spacingOneIsSequential() {
        let wave = HandleGradeWave(crestHalfWidth: 0.2, repetitions: 4, spacing: 1)
        let count = 24
        for step in 0...80 {
            #expect(litRunCount(wave, count: count, progress: Double(step) / 80) <= 1)
        }
    }

    @Test("Overlapping spacing puts several crests on the string at the same time")
    func overlapProducesSimultaneousCrests() {
        let count = 24
        let sequential = HandleGradeWave(crestHalfWidth: 0.15, repetitions: 4, spacing: 1)
        let overlapping = HandleGradeWave(crestHalfWidth: 0.15, repetitions: 4, spacing: 0.35)

        func maxSimultaneousRuns(_ wave: HandleGradeWave) -> Int {
            (0...100).map { litRunCount(wave, count: count, progress: Double($0) / 100) }.max() ?? 0
        }
        #expect(maxSimultaneousRuns(sequential) == 1)
        #expect(maxSimultaneousRuns(overlapping) >= 2)
    }

    @Test("The animation rests at both ends for any spacing")
    func spacingRestsAtEnds() {
        let wave = HandleGradeWave(crestHalfWidth: 0.3, repetitions: 4, spacing: 0.3)
        let count = 10
        for index in 0..<count {
            #expect(wave.intensity(characterIndex: index, count: count, progress: 0) < 0.0001)
            #expect(wave.intensity(characterIndex: index, count: count, progress: 1) < 0.0001)
        }
    }

    @Test("Spacing is clamped: an over-range value behaves like the nearest bound")
    func spacingClamped() {
        let count = 16
        let atMax = HandleGradeWave(crestHalfWidth: 0.2, repetitions: 3, spacing: 1)
        let overMax = HandleGradeWave(crestHalfWidth: 0.2, repetitions: 3, spacing: 2)
        for step in 0...40 {
            let progress = Double(step) / 40
            for index in 0..<count {
                #expect(overMax.intensity(characterIndex: index, count: count, progress: progress)
                    == atMax.intensity(characterIndex: index, count: count, progress: progress))
            }
        }
    }

    @Test("Normalized span grows by the spacing for each extra repetition")
    func normalizedSpanScales() {
        #expect(HandleGradeWave(repetitions: 1, spacing: 0.4).normalizedSpan == 1)
        #expect(abs(HandleGradeWave(repetitions: 3, spacing: 1).normalizedSpan - 3) < 0.0001)
        #expect(abs(HandleGradeWave(repetitions: 3, spacing: 0.5).normalizedSpan - 2) < 0.0001)
    }

    // MARK: - Helpers

    /// The index of the most strongly lit letter at an instant.
    private func mostIntenseIndex(_ wave: HandleGradeWave, count: Int, at progress: Double) -> Int {
        (0..<count).max { lhs, rhs in
            wave.intensity(characterIndex: lhs, count: count, progress: progress)
                < wave.intensity(characterIndex: rhs, count: count, progress: progress)
        }!
    }

    /// The number of contiguous runs of lit (nonzero-intensity) letters at an
    /// instant — one per crest currently on the string.
    private func litRunCount(_ wave: HandleGradeWave, count: Int, progress: Double) -> Int {
        var runs = 0
        var inRun = false
        for index in 0..<count {
            let lit = wave.intensity(characterIndex: index, count: count, progress: progress) > 0.0017
            if lit && !inRun { runs += 1 }
            inRun = lit
        }
        return runs
    }
}
