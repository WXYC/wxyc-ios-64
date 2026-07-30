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

    /// How many crests sweep across the handle over one animation, `>= 1`. Because
    /// each crest enters and exits off the ends at rest, the two global endpoints
    /// sit at ``baseGrade``, so the handle still begins and ends at its normal
    /// metrics however the crests are spaced.
    public var repetitions: Int

    /// The launch interval between consecutive crests, as a fraction of one
    /// sweep's travel, `(0, 1]`. At `1` the crests are sequential — each finishes
    /// and the letters rest before the next enters. Below `1` the crests overlap,
    /// so several sweep the handle at once and the whole animation packs into less
    /// time (``normalizedSpan`` sweeps rather than ``repetitions``), reading as a
    /// snappier train instead of one pass at a time.
    public var spacing: Double

    public init(
        baseGrade: Double = SFProFontAxis.grade.defaultValue,
        depth: Double = 336,
        crestHalfWidth: Double = 0.35,
        repetitions: Int = 1,
        spacing: Double = 1
    ) {
        self.baseGrade = baseGrade
        self.depth = depth
        self.crestHalfWidth = crestHalfWidth
        self.repetitions = repetitions
        self.spacing = spacing
    }

    /// The spacing clamped to a usable `(0, 1]`.
    private var clampedSpacing: Double {
        min(max(spacing, .ulpOfOne), 1)
    }

    /// The animation's length in single-sweep units: `1` for a lone crest, growing
    /// by ``spacing`` for each additional crest. The view scales the per-sweep
    /// ``HandleGradeWave`` duration by this, so overlapping crests (spacing < 1)
    /// finish in proportionally less time.
    public var normalizedSpan: Double {
        Double(max(1, repetitions) - 1) * clampedSpacing + 1
    }

    /// The grade for the letter at `index` (of `count` letters) at animation
    /// `progress` in `0...1`.
    ///
    /// A train of ``repetitions`` crests sweeps across the string, each launching
    /// ``spacing`` sweeps after the last. A crest's center travels from just before
    /// the first letter to just past the last, lightening the letters within a
    /// ``crestHalfWidth`` of it by a raised-cosine bump that peaks at
    /// `baseGrade − depth` dead-center. At both endpoints no crest is mid-sweep, so
    /// the whole string sits at ``baseGrade``; when ``spacing`` is below `1` several
    /// crests overlap the string at once, and where two cover the same letter the
    /// deeper lightening wins so the dip never exceeds ``depth``.
    ///
    /// - Parameters:
    ///   - index: The letter's position, `0..<count`.
    ///   - count: The number of letters in the handle. Non-positive counts return
    ///     ``baseGrade`` defensively.
    ///   - progress: The animation phase, clamped into `0...1`.
    /// - Returns: The grade-axis value for that letter at that instant.
    public func grade(characterIndex index: Int, count: Int, progress: Double) -> Double {
        baseGrade - depth * intensity(characterIndex: index, count: count, progress: progress)
    }

    /// The wave's intensity for the letter at `index` — how strongly the crest
    /// train lights it at animation `progress`, `0` (untouched) ... `1` (a crest
    /// centered dead on it).
    ///
    /// This is the pure spatial/temporal shape of the wave, independent of any
    /// font axis: ``grade(characterIndex:count:progress:)`` maps it onto the grade
    /// axis, and a caller can map the same value onto others (e.g. weight, for a
    /// thinner crest) since the handle's fixed per-letter cells keep the total
    /// width constant whatever axis moves.
    ///
    /// - Parameters:
    ///   - index: The letter's position, `0..<count`.
    ///   - count: The number of letters in the handle. Non-positive counts return
    ///     `0` defensively.
    ///   - progress: The animation phase, clamped into `0...1`.
    /// - Returns: The lighting intensity for that letter at that instant, `0...1`.
    public func intensity(characterIndex index: Int, count: Int, progress: Double) -> Double {
        guard count > 0 else { return 0 }

        let progress = min(max(progress, 0), 1)
        let halfWidth = max(crestHalfWidth, .ulpOfOne)
        let repetitions = max(1, self.repetitions)
        let spacing = clampedSpacing

        // The letter's position along the string, 0 (first) ... 1 (last). A
        // single-letter handle sits at 0.
        let position = count <= 1 ? 0 : Double(index) / Double(count - 1)

        // Run a train of crests across the string. Sweep-time advances from 0 to
        // `normalizedSpan` over the animation; crest i launches `spacing` sweeps
        // after crest i-1, so when spacing < 1 several are mid-sweep at once. A
        // crest is on the string only while its phase is in (0, 1), so both global
        // endpoints — where none is mid-sweep — rest (intensity 0).
        let sweepTime = progress * normalizedSpan
        var peak = 0.0
        for crest in 0..<repetitions {
            let phase = sweepTime - Double(crest) * spacing
            guard phase > 0, phase < 1 else { continue }

            // The crest center travels -halfWidth (before the first letter) to
            // 1 + halfWidth (past the last), so it enters and exits at rest.
            let crestCenter = -halfWidth + phase * (1 + 2 * halfWidth)
            let distance = (position - crestCenter) / halfWidth
            guard abs(distance) < 1 else { continue }

            // Raised cosine: 1 at the crest center, easing to 0 at its edges.
            // Where crests overlap a letter the strongest wins, so intensity
            // never exceeds 1.
            peak = max(peak, 0.5 * (1 + cos(.pi * distance)))
        }
        return peak
    }
}
