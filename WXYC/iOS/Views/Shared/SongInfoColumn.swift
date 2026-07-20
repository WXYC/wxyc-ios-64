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
struct SongInfoColumn<Detail: View>: View {
    let song: any SongDisplayable
    @ViewBuilder var detailLine: () -> Detail

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(song.songTitle)
                .fontWeight(.bold)
                .foregroundStyle(.white)
            Text(song.artistName)
                .foregroundStyle(.white)
            detailLine()
        }
    }
}
