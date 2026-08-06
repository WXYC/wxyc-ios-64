//
//  HandleWaveAxes.swift
//  WXUI
//
//  The on-air handle wave's presentation math: how the banner turns a crest
//  ``HandleGradeWave/intensity(characterIndex:count:progress:)`` into per-letter
//  SF Pro axis values, and elapsed time into a clamped animation progress.
//
//  Split out from the view so this logic is unit-tested without a view host: the
//  view builds a ``HandleWaveAxes`` from the theme and, per letter per frame, feeds
//  it the wave intensity to get the letter's grade and weight.
//
//  Created by Jake Bromberg on 07/30/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Maps a wave crest ``HandleGradeWave/intensity(characterIndex:count:progress:)``
/// onto the SF Pro grade and weight axes for one letter. Each axis dips linearly
/// from its resting value toward a lighter, thinner glyph as intensity rises: at
/// intensity 0 both sit at rest (the normal look), and at 1 each reaches its
/// resting value minus its depth.
///
/// Grade is metric-neutral; weight is not — but the handle pins each letter to a
/// fixed cell, so the total width is constant however far weight drops. The axes
/// are independent: a zero depth leaves that axis at rest regardless of the other.
public struct HandleWaveAxes: Hashable, Sendable {
    /// The letter's resting grade — the value at intensity 0.
    public var restingGrade: Double

    /// How far grade dips at full intensity (subtracted at intensity 1).
    public var gradeDepth: Double

    /// The letter's resting weight — the value at intensity 0.
    public var restingWeight: Double

    /// How far weight dips at full intensity (subtracted at intensity 1). Grade
    /// bottoms out well short of hairline, so weight carries a thin crest.
    public var weightDepth: Double

    public init(restingGrade: Double, gradeDepth: Double, restingWeight: Double, weightDepth: Double) {
        self.restingGrade = restingGrade
        self.gradeDepth = gradeDepth
        self.restingWeight = restingWeight
        self.weightDepth = weightDepth
    }

    /// The grade-axis value for a letter at the given wave `intensity` (`0...1`).
    public func grade(atIntensity intensity: Double) -> Double {
        restingGrade - gradeDepth * intensity
    }

    /// The weight-axis value for a letter at the given wave `intensity` (`0...1`).
    public func weight(atIntensity intensity: Double) -> Double {
        restingWeight - weightDepth * intensity
    }
}

/// The elapsed fraction of the whole wave, clamped to `0...1`. Returns `1` when
/// there is no time to animate (`totalDuration <= 0`) — the resting frame — so a
/// disabled or zero-length wave settles at its endpoint rather than dividing by
/// zero.
public func handleWaveProgress(elapsed: TimeInterval, totalDuration: TimeInterval) -> Double {
    guard totalDuration > 0 else { return 1 }
    return min(max(elapsed / totalDuration, 0), 1)
}
