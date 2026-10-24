//
//  RowArtworkSlot.swift
//  WXYC
//
//  The leading artwork slot of a song row, extracted from `SongRowContent` so a
//  row with different artwork can sit in the same frame: padded, clipped to the
//  concentric row shape, and capped at a 2.5th of the row's width. It is
//  content-agnostic; the artwork's own shape, glass and scroll-leaning shadow
//  come from `RowArtworkFrame` and `ArtworkStyle`.
//
//  Created by Jake Bromberg on 10/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI

struct RowArtworkSlot<Artwork: View>: View {
    /// The width of the enclosing row (the `GeometryProxy`'s width).
    let rowWidth: CGFloat
    @ViewBuilder var artwork: () -> Artwork

    var body: some View {
        artwork()
            .padding(SongRowMetrics.artworkPadding)
            .clipRounded()
            .frame(maxWidth: SongRowMetrics.artworkSlotWidth(rowWidth: rowWidth), alignment: .leading)
    }
}
