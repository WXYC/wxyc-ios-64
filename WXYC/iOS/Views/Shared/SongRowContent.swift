//
//  SongRowContent.swift
//  WXYC
//
//  The artwork + info + trailing-control layout shared by the flowsheet row
//  (`PlaycutRowView`) and the Liked tab row (`LikedSongRow`). Both render it
//  inside a 2.5-aspect `GeometryReader`, so the artwork is sized identically —
//  `proxy.size.width / 2.5` — on both surfaces. The detail line (play time vs.
//  "liked N ago") and the trailing control (toggle heart vs. unlike heart) are
//  injected per-row via slots; everything else is shared so the two lists
//  present a song the same way.
//
//  Created by Jake Bromberg on 07/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Artwork
import Playlist
import SwiftUI
import WXUI

/// The song-row body — artwork, the `SongInfoColumn`, and a trailing control —
/// laid out to fill a 2.5-aspect row. The caller owns the `GeometryReader`
/// (its `proxy` sizes the artwork) and the row background; this view is the
/// content shared by the flowsheet and the Liked tab so a song's artwork and
/// text read the same on both.
struct SongRowContent<Song: SongDisplayable, Detail: View, Trailing: View>: View {
    let song: Song
    let artworkState: ArtworkLoader.State
    /// Scroll-driven shadow lean; the flowsheet feeds a live value, the Liked
    /// row leaves it at rest.
    var shadowYOffset: CGFloat = 0
    /// Built lazily: only the failed-artwork placeholder reads it, so the common
    /// loaded/loading rows never allocate a gradient (and a nil palette never
    /// regenerates its random colors on a row that isn't showing the placeholder).
    let meshGradient: () -> AnimatedMeshGradient
    let proxy: GeometryProxy
    @ViewBuilder var detailLine: () -> Detail
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Artwork — sized to the row via the caller's proxy, so the flowsheet
            // and the Liked row render the identical dimensions.
            Group {
                switch artworkState {
                case .loaded(let image):
                    LoadedArtworkView(artwork: image, shadowYOffset: shadowYOffset)
                case .unloaded, .loading:
                    LoadingArtworkView(shadowYOffset: shadowYOffset)
                case .failed:
                    PlaceholderArtworkView(
                        cornerRadius: ArtworkStyle.cornerRadius,
                        shadowYOffset: shadowYOffset,
                        meshGradient: meshGradient()
                    )
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: proxy.size.height * 0.75
                    )
                }
            }
            .padding(12.0)
            .clipRounded()
            .frame(maxWidth: proxy.size.width / 2.5, alignment: .leading)

            // Song info — title/artist shared; the detail line is per-row.
            SongInfoColumn(song: song, detailLine: detailLine)

            // Guarantee a gutter before the trailing control even when the title
            // consumes the row's width, so text never abuts the 44pt tap target.
            Spacer(minLength: 8)

            trailing()
        }
    }
}
