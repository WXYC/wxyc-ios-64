//
//  SongInfoColumn.swift
//  WXYC
//
//  The title / artist / detail text column shared by the flowsheet row
//  (`PlaycutRowView`) and the Liked tab row (`LikedSongRow`). Both feed it any
//  `SongDisplayable`, so a song's title and artist render identically across the
//  two lists; the third line — the flowsheet's play time vs. the Liked row's
//  "liked N ago" — is injected per-row via the `detailLine` slot, since that is
//  the part the two rows should render differently.
//
//  Created by Jake Bromberg on 07/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Playlist
import SwiftUI

/// The leading text column of a song row: bold title over artist over a
/// caller-supplied detail line. Typography matches the flowsheet so the Liked
/// tab presents a song the same way the playlist does.
struct SongInfoColumn<Song: SongDisplayable, Detail: View>: View {
    let song: Song
    @ViewBuilder var detailLine: () -> Detail

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Line limits match the row's fixed 2.5 aspect: title over two lines,
            // artist over one, so a long title truncates rather than overflowing
            // the fixed height. Both surfaces share the caps so they stay in sync.
            Text(song.songTitle)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .lineLimit(2)
            Text(song.artistName)
                .foregroundStyle(.white)
                .lineLimit(1)
            detailLine()
        }
    }
}
