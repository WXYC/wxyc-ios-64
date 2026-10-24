//
//  SongRowMetrics.swift
//  WXYC
//
//  The sizing shared by the song row's card and its artwork slot: the row is 2.5
//  times wider than it is tall, and the artwork sits in a slot one 2.5th of the
//  row's width with 12pt of padding. `SongRowPanel` and `RowArtworkSlot` both
//  read these numbers so they cannot drift apart.
//
//  Created by Jake Bromberg on 10/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI

nonisolated enum SongRowMetrics {
    /// Width over height of a song row.
    static let aspectRatio: CGFloat = 2.5

    /// Padding on every side of the artwork inside its slot.
    static let artworkPadding: CGFloat = 12

    /// Corner radius of the song row's card. `SongRowPanel` defaults to it and
    /// `SpecialtyCardView` reads it, so the specialty card matches the rows below.
    static let cornerRadius: CGFloat = 12

    /// The scroll-leaning shadow's vertical offset when the row is at the top of
    /// the screen, and when it is at the bottom. Read by `PlaycutRowView` and
    /// `SpecialtyCardView`.
    static let shadowOffsetAtTop: CGFloat = -3
    static let shadowOffsetAtBottom: CGFloat = 3

    /// The width of the leading artwork slot in a row `rowWidth` points wide.
    static func artworkSlotWidth(rowWidth: CGFloat) -> CGFloat {
        rowWidth / aspectRatio
    }

    /// The side of the square artwork inside the slot: the slot's width less the
    /// padding on both sides, never negative.
    static func artworkSide(rowWidth: CGFloat) -> CGFloat {
        max(artworkSlotWidth(rowWidth: rowWidth) - 2 * artworkPadding, 0)
    }
}
