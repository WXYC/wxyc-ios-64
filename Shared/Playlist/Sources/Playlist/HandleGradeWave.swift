//
//  HandleGradeWave.swift
//  Playlist
//
//  A one-shot "wave" for the on-air DJ handle: a train of lightening crests that
//  sweep across the letters once when the handle appears or changes.
//
//  This model is the wave's pure *shape* — for each letter, at each moment, how
//  strongly a crest lights it (``intensity``), from 0 (untouched) to 1 (a crest
//  centered dead on it). It knows nothing about fonts: the view maps that
//  intensity onto SF Pro axes (grade for a subtle, metric-neutral dip; weight for
//  a thinner crest). Every letter rests at intensity 0 at progress 0 and 1, so the
//  handle starts and ends at its normal look and the animation reads as a single
//  pass.
//
//  Being pure (no font, no view, no clock), the crest shape and its boundary
//  behavior are unit-tested without a device.
//
//  Created by Jake Bromberg on 07/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// The shape of the on-air handle's lightening "wave": a train of raised-cosine
/// crests that sweep across the letters and return them to rest. It reports a
/// per-letter ``intensity(characterIndex:count:progress:)`` in `0...1` that the
/// view maps onto whatever font axes thin a glyph; because the handle pins each
/// letter to a fixed cell, the total width is unchanged whatever axis moves.
public struct HandleGradeWave: Hashable, Sendable {
    /// The crest's half-width as a fraction of the whole string, `(0, 1]`. Larger
    /// values light more letters at once (a broad swell); smaller values light a
    /// tighter band (a crisp highlight sweeping letter to letter).
    public var crestHalfWidth: Double

    /// How many crests sweep across the handle over one animation, `>= 1`. Because
    /// each crest enters and exits off the ends at rest, the two global endpoints
    /// sit at intensity 0, so the handle still begins and ends at its normal look
    /// however the crests are spaced.
    public var repetitions: Int

    /// The launch interval between consecutive crests, as a fraction of one
    /// sweep's travel, `(0, 1]`. At `1` the crests are sequential — each finishes
    /// and the letters rest before the next enters. Below `1` the crests overlap,
    /// so several sweep the handle at once and the whole animation packs into less
    /// time (``normalizedSpan`` sweeps rather than ``repetitions``), reading as a
    /// snappier train instead of one pass at a time.
    public var spacing: Double

    public init(
        crestHalfWidth: Double = 0.35,
        repetitions: Int = 1,
        spacing: Double = 1
    ) {
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
    /// duration by this, so overlapping crests (spacing < 1) finish in
    /// proportionally less time.
    public var normalizedSpan: Double {
        Double(max(1, repetitions) - 1) * clampedSpacing + 1
    }

    /// The wave's intensity for the letter at `index` (of `count` letters) at
    /// animation `progress` in `0...1` — how strongly the crest train lights it,
    /// `0` (untouched) ... `1` (a crest centered dead on it).
    ///
    /// A train of ``repetitions`` crests sweeps across the string, each launching
    /// ``spacing`` sweeps after the last. A crest's center travels from just before
    /// the first letter to just past the last, lighting the letters within a
    /// ``crestHalfWidth`` of it by a raised-cosine bump that peaks at `1`
    /// dead-center. At both endpoints no crest is mid-sweep, so the whole string
    /// rests at `0`; when ``spacing`` is below `1` several crests overlap the
    /// string at once, and where two cover the same letter the stronger wins so
    /// intensity never exceeds `1`.
    ///
    /// The view maps this onto SF Pro axes (grade, weight); it's the pure
    /// spatial/temporal shape of the wave, independent of any font.
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
