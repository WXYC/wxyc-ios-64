//
//  PerLetterHandleGate.swift
//  Playlist
//
//  Decides whether the on-air DJ handle renders as the rigid per-letter row (the
//  wave row) or the flexible single `Text`. The per-letter row pins each glyph to
//  a fixed cell, so it can neither wrap nor compress — it must only appear once
//  its width is settled, or it overflows beside the say-hi chip. Pure and
//  view-free, so the startup gate is unit-tested without a device.
//
//  Created by Jake Bromberg on 07/30/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import CoreGraphics

/// Whether the on-air handle should render as the per-letter row rather than a
/// single native `Text`.
///
/// The per-letter row (one `Text` per glyph, each pinned to its kerned base-metric
/// advance) is rigid: it can't wrap and it can't compress. So it must render only
/// at its resolved, fitted width. On the first layout pass the available width is
/// still zero — the adaptive fit hasn't been solved, and the effective width sits
/// at the unfitted base (expanded) axis — so a per-letter row there would run wide
/// and overflow beside the say-hi chip for a frame before snapping to the fitted
/// width. Until the width resolves, the caller falls back to the single `Text`,
/// which wraps or compresses gracefully. When the adaptive fit is off, the base
/// width *is* the final width, so there is nothing to wait for.
///
/// - Parameters:
///   - waveEnabled: Whether the handle plays its one-shot wave at all.
///   - shapesOneGlyphPerCharacter: Whether the handle shapes to exactly one glyph
///     per character (so each letter can be pinned to its own cell); false for a
///     ligature, combining mark, or non-BMP scalar.
///   - adaptiveWidth: Whether the handle condenses its width axis to fit one line.
///   - availableWidth: The measured space the handle may occupy; zero until the
///     first layout pass reports it.
/// - Returns: `true` to render the per-letter row, `false` to use the single `Text`.
public func shouldRenderPerLetterHandle(
    waveEnabled: Bool,
    shapesOneGlyphPerCharacter: Bool,
    adaptiveWidth: Bool,
    availableWidth: CGFloat
) -> Bool {
    let widthResolved = !adaptiveWidth || availableWidth > 0
    return waveEnabled && shapesOneGlyphPerCharacter && widthResolved
}
