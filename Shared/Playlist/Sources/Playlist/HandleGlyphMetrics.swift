//
//  HandleGlyphMetrics.swift
//  Playlist
//
//  Measures how much horizontal space each character of the on-air DJ handle
//  occupies in its real, shaped line — kerning included — so the handle's grade
//  wave can be drawn letter-by-letter without widening.
//
//  The wave varies each letter's grade, which a single `Text` can't do, so the
//  animating handle is a row of one `Text` per character. An `HStack` of `Text`s
//  lays each glyph at its own advance with no kerning between them, so the row is
//  a touch wider than the kerned single `Text` it swaps with — the handle appears
//  to breathe. Pinning each letter's cell to the advance measured here (the gap
//  to the next glyph's origin in the shaped line, which folds kerning in) makes
//  the row total the single line's width exactly, so nothing shifts.
//
//  Pure CoreText, no view or font state, so it's unit-tested without a device.
//
//  Created by Jake Bromberg on 07/30/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import CoreGraphics
import CoreText
import Foundation

/// The per-character advance widths of `string` laid out on one line in `font`,
/// with kerning folded in — i.e. how much horizontal room each character takes
/// in the real shaped line.
///
/// The advances sum to the line's typographic width, so a row of per-character
/// views pinned to these widths matches the width of the single laid-out string
/// (kerning included) rather than running wide the way an un-kerned `HStack` of
/// `Text`s would.
///
/// - Returns: One advance per `Character`, in reading order; `[]` for the empty
///   string; or `nil` when the shaped glyphs don't map one-to-one to the string's
///   characters (a ligature, combining marks, or a non-BMP scalar), so the caller
///   can fall back to laying the handle out as a single view.
public func handleCharacterAdvances(for string: String, font: CTFont) -> [CGFloat]? {
    let characters = Array(string)
    guard !characters.isEmpty else { return [] }

    let attributed = NSAttributedString(
        string: string,
        attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
    )
    let line = CTLineCreateWithAttributedString(attributed)
    let totalWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))

    guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return nil }

    // Collect every glyph's origin x and the character index it shaped from,
    // across all runs, then order them left to right.
    var glyphs: [(stringIndex: Int, x: CGFloat)] = []
    for run in runs {
        let count = CTRunGetGlyphCount(run)
        guard count > 0 else { continue }
        var positions = [CGPoint](repeating: .zero, count: count)
        var indices = [CFIndex](repeating: 0, count: count)
        CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
        CTRunGetStringIndices(run, CFRange(location: 0, length: count), &indices)
        for glyph in 0..<count {
            glyphs.append((stringIndex: indices[glyph], x: positions[glyph].x))
        }
    }

    // Only a clean one-glyph-per-character shaping can be attributed back to the
    // characters; anything else (ligature, combining mark, surrogate pair) bails
    // to the single-view fallback.
    guard glyphs.count == characters.count else { return nil }
    glyphs.sort { $0.stringIndex < $1.stringIndex }

    // Each character's advance is the distance to the next glyph's origin; the
    // last runs to the line's trailing edge. Origin-to-origin deltas fold the
    // kerning between neighbors in automatically.
    return glyphs.indices.map { index in
        let nextX = index + 1 < glyphs.count ? glyphs[index + 1].x : totalWidth
        return max(0, nextX - glyphs[index].x)
    }
}
