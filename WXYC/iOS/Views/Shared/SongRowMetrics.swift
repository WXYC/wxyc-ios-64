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

enum SongRowMetrics {
    /// Width over height of a song row.
    static let aspectRatio: CGFloat = 2.5

    /// Padding on every side of the artwork inside its slot.
    static let artworkPadding: CGFloat = 12

    /// The width of the leading artwork slot in a row `rowWidth` points wide.
    static func artworkSlotWidth(rowWidth: CGFloat) -> CGFloat {
        rowWidth / aspectRatio
    }
}
