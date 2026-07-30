//
//  HandleGradeWave.swift
//  Playlist
//
//  A one-shot "wave" for the on-air DJ handle: a single lightening crest that
//  sweeps across the letters once when the handle appears or changes.
//
//  The wave modulates only SF Pro's grade (`GRAD`) axis. Grade is metric-neutral
//  — it changes a glyph's apparent weight without changing its advance width — so
//  the handle's total horizontal width is unchanged while the wave plays. Every
//  letter rests at ``baseGrade`` at progress 0 and 1, so the string starts and
//  ends at its normal display metrics and the animation reads as a single pass.
//
//  The model is pure (no font, no view, no clock), so the crest shape and its
//  boundary behavior are unit-tested without a device.
//
//  Created by Jake Bromberg on 07/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// A single lightening crest that sweeps across the DJ handle's letters exactly
/// once by lowering SF Pro's grade axis, then returns every letter to its resting
/// grade. Because only grade moves, the handle's width is unaffected.
public struct HandleGradeWave: Hashable, Sendable {
    /// The resting grade — the value every letter holds at progress 0 and 1, and
    /// the value the crest lightens *away from*. Set to the handle's display grade
    /// so the wave begins and ends at the normal look.
    public var baseGrade: Double

    /// How far, in grade units, the crest lightens a letter at its peak. The most
    /// affected letter reaches `baseGrade − depth`. The handle ships near the top
    /// of the grade range, so the wave lightens (dips grade) rather than darkens —
    /// there's far more travel below the resting grade than above it.
    public var depth: Double

    /// The crest's half-width as a fraction of the whole string, `(0, 1]`. Larger
    /// values light more letters at once (a broad swell); smaller values light a
    /// tighter band (a crisp highlight sweeping letter to letter).
    public var crestHalfWidth: Double

    /// How many times the crest sweeps across the handle over one animation, `>= 1`.
    /// The sweeps run back to back; because each one enters and exits off the ends
    /// at rest, the seams between them — and the two global endpoints — all sit at
    /// ``baseGrade``, so the handle still begins and ends at its normal metrics.
    public var repetitions: Int

    public init(
        baseGrade: Double = SFProFontAxis.grade.defaultValue,
        depth: Double = 336,
        crestHalfWidth: Double = 0.35,
        repetitions: Int = 1
    ) {
        self.baseGrade = baseGrade
        self.depth = depth
        self.crestHalfWidth = crestHalfWidth
        self.repetitions = repetitions
    }

    /// The grade for the letter at `index` (of `count` letters) at animation
    /// `progress` in `0...1`.
    ///
    /// The crest center sweeps from just before the first letter to just past the
    /// last as progress runs 0 → 1, so at both endpoints no letter lies under the
    /// crest and the whole string sits at ``baseGrade``. Between the endpoints a
    /// raised-cosine bump lightens the letters within a ``crestHalfWidth`` of the
    /// crest, peaking at `baseGrade − depth` for the letter dead-center.
    ///
    /// - Parameters:
    ///   - index: The letter's position, `0..<count`.
    ///   - count: The number of letters in the handle. Non-positive counts return
    ///     ``baseGrade`` defensively.
    ///   - progress: The animation phase, clamped into `0...1`.
    /// - Returns: The grade-axis value for that letter at that instant.
    public func grade(characterIndex index: Int, count: Int, progress: Double) -> Double {
        guard count > 0 else { return baseGrade }

        let progress = min(max(progress, 0), 1)
        let halfWidth = max(crestHalfWidth, .ulpOfOne)

        // Fold the whole animation into `repetitions` back-to-back sweeps: the
        // fractional part of (progress × repetitions) is the phase within the
        // current sweep. At a seam it lands on 0 (a fresh sweep about to enter
        // from the left), and at the global end progress × repetitions is a whole
        // number, so the phase is 0 — every boundary rests at the base grade.
        let repetitions = max(1, self.repetitions)
        let scaled = progress * Double(repetitions)
        let sweepProgress = scaled - scaled.rounded(.down)

        // The letter's position along the string, 0 (first) ... 1 (last). A
        // single-letter handle sits at 0.
        let position = count <= 1 ? 0 : Double(index) / Double(count - 1)

        // Sweep the crest from -halfWidth (before the first letter) to
        // 1 + halfWidth (past the last), so the ends are always at rest.
        let crestCenter = -halfWidth + sweepProgress * (1 + 2 * halfWidth)

        // Normalized distance from the crest, in half-widths. Beyond one
        // half-width the letter is untouched.
        let distance = (position - crestCenter) / halfWidth
        guard abs(distance) < 1 else { return baseGrade }

        // Raised cosine: 1 at the crest center, easing to 0 at the crest edges.
        let bump = 0.5 * (1 + cos(.pi * distance))
        return baseGrade - depth * bump
    }
}
