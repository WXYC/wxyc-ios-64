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
import UIKit
import Wallpaper
import WXUI

/// A single liked-song row. The heart is always filled here — every row in
/// this list is liked by construction; tapping it unlikes and removes the row.
struct LikedSongRow: View {
    let snapshot: LikedSongSnapshot
    let onSelect: (UIImage?) -> Void
    let onUnlike: () -> Void

    /// The snapshot bridged back to a `Playcut`, built once per row — it keys
    /// the artwork loader and feeds the detail card on tap.
    private let playcut: Playcut

    @Environment(Singletonia.self) private var appState

    init(snapshot: LikedSongSnapshot, onSelect: @escaping (UIImage?) -> Void, onUnlike: @escaping () -> Void) {
        self.snapshot = snapshot
        self.onSelect = onSelect
        self.onUnlike = onUnlike
        self.playcut = snapshot.toPlaycut()
    }

    private var artworkState: ArtworkLoader.State {
        appState.artworkLoader.state(for: playcut)
    }

    private var loadedArtwork: UIImage? {
        if case .loaded(let image) = artworkState { image } else { nil }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            artworkThumbnail

            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.songTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(snapshot.artistName)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                Text("Liked \(snapshot.likedAt, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            LikeHeartButton(isLiked: true, action: onUnlike)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The same theme-aware material as the playcut and On Tour rows, so the
        // three list surfaces match.
        .background(BackgroundLayer(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.12), lineWidth: 1))
        .contentShape(.rect(cornerRadius: 12))
        .onTapGesture {
            onSelect(loadedArtwork)
        }
        .onAppear {
            // Idempotent: coalesces with in-flight loads and short-circuits when
            // already loaded. The playlist's prune pass may evict a liked row's
            // entry between visits; reappearing re-requests it.
            appState.artworkLoader.load(playcut)
        }
    }

    @ViewBuilder
    private var artworkThumbnail: some View {
        Group {
            switch artworkState {
            case .loaded(let image):
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .unloaded, .loading:
                LoadingArtworkView(shadowYOffset: 0)
            case .failed:
                PlaceholderArtworkView(cornerRadius: 8)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
