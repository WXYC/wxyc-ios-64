//
//  LikedSongRow.swift
//  WXYC
//
//  One liked song in the Liked tab's list (#492): artwork thumbnail via the
//  shared ArtworkLoader (placeholder when unresolvable), title, artist, and the
//  liked date, with a filled heart that unlikes in place. Tapping the row opens
//  the standard playcut detail card from the snapshot's `toPlaycut()` bridge.
//
//  Created by Jake Bromberg on 07/18/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Artwork
import LikedSongs
import Playlist
import SwiftUI
import Wallpaper
import WXUI

/// A single liked-song row. The heart is always filled here — every row in
/// this list is liked by construction; tapping it unlikes and removes the row.
struct LikedSongRow: View {
    let snapshot: LikedSongSnapshot
    /// The zoom-transition namespace shared with the detail cover, so this row is
    /// the source the `PlaycutDetailView` animates out of (mirrors `ConcertRow`).
    let namespace: Namespace.ID
    let onSelect: (PlatformImage?) -> Void
    let onUnlike: () -> Void

    /// The snapshot bridged back to a `Playcut`, built once per row — it keys
    /// the artwork loader and feeds the detail card on tap.
    private let playcut: Playcut

    @Environment(Singletonia.self) private var appState
    @Environment(\.wallpaperMeshGradientPalette) private var wallpaperPalette

    /// Stable time offset for the failed-artwork mesh gradient, matching the
    /// flowsheet row (randomized once at init).
    private let stableTimeOffset = TimeInterval((-10..<10).randomElement()!)

    init(snapshot: LikedSongSnapshot, namespace: Namespace.ID, onSelect: @escaping (PlatformImage?) -> Void, onUnlike: @escaping () -> Void) {
        self.snapshot = snapshot
        self.namespace = namespace
        self.onSelect = onSelect
        self.onUnlike = onUnlike
        self.playcut = snapshot.toPlaycut()
    }

    private var artworkState: ArtworkLoader.State {
        appState.artworkLoader.state(for: playcut)
    }

    private var loadedArtwork: PlatformImage? {
        if case .loaded(let image) = artworkState { image } else { nil }
    }

    var body: some View {
        // The shared card chrome (same theme-aware material as the flowsheet and
        // On Tour rows, so the three list surfaces match); `stroked` keeps the
        // Liked row's hairline border, which the flowsheet's plain row omits.
        SongRowPanel(stroked: true, onTap: { onSelect(loadedArtwork) }) { proxy in
            // The shared flowsheet row body — same artwork size, same text column
            // — with the liked-relative date as this row's detail line and the
            // unlike heart in the trailing slot. The mesh gradient is built lazily
            // and only read by the failed-artwork placeholder.
            SongRowContent(
                song: snapshot,
                artworkState: artworkState,
                meshGradient: { AnimatedMeshGradient(colors: wallpaperPalette, timeOffset: stableTimeOffset) },
                proxy: proxy
            ) {
                Text("Liked \(snapshot.likedAt, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            } trailing: {
                LikeHeartButton(isLiked: true, action: onUnlike)
                    .padding(.trailing, 4)
            }
        }
        // Source for the detail cover's zoom transition — the whole card is what
        // animates into `PlaycutDetailView`. Keyed on the snapshot's stable id,
        // not `playcut.id`: `toPlaycut()` hardcodes id 0, so every liked row would
        // otherwise register the same source and the zoom couldn't pick this one.
        .zoomTransitionSource(id: snapshot.id, in: namespace)
        .onAppear {
            // Idempotent: coalesces with in-flight loads and short-circuits when
            // already loaded. The playlist's prune pass may evict a liked row's
            // entry between visits; reappearing re-requests it.
            appState.artworkLoader.load(playcut)
        }
    }
}
