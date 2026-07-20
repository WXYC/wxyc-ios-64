//
//  LikedTabView.swift
//  WXYC
//
//  The Liked tab (#492): a newest-first list of the listener's liked songs from
//  the on-device LikedSongsStore. Rows unlike via swipe or heart-off; tapping a
//  row reopens the standard playcut detail card through the tab's own overlay
//  sheet (the root's presentation state stays private to RootTabView). Likes
//  never leave the device; the toggle analytics carry no song identity.
//
//  Created by Jake Bromberg on 07/18/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import LikedSongs
import SwiftUI
import WXUI

/// The root view of the Liked tab.
struct LikedTabView: View {
    @Environment(Singletonia.self) private var appState
    /// The tab's own detail-card presentation, mirroring `RootTabView`'s
    /// `selectedPlaycut` + `.overlaySheet` pattern — the root's state is
    /// `private`, so this tab presents from its own.
    @State private var selectedPlaycut: PlaycutSelection?

    #if DEBUG
    /// The like-effect tuning bench, opened by tapping the "Liked" header.
    @State private var showEffectTuning = false
    #endif

    var body: some View {
        content
            .accessibilityIdentifier("likedTabView")
            .overlaySheet(isPresented: Binding(
                get: { selectedPlaycut != nil },
                set: { if !$0 { selectedPlaycut = nil } }
            )) {
                if let selection = selectedPlaycut {
                    PlaycutDetailView(playcut: selection.playcut, artwork: selection.artwork)
                }
            }
            #if DEBUG
            .sheet(isPresented: $showEffectTuning) {
                LikeEffectTuningView()
            }
            #endif
    }

    // MARK: - Header

    /// Wraps the non-scrolling empty state under a static header, so the title
    /// still shows when there's no list to scroll it with.
    private func staticLayout(@ViewBuilder _ body: () -> some View) -> some View {
        VStack(spacing: 0) {
            header
            body()
        }
    }

    private var header: some View {
        #if DEBUG
        // The title doubles as the entry point to the like-effect tuning bench.
        // A plain-styled button keeps the heading's look while making it tappable
        // without an `onTapGesture`.
        Button {
            showEffectTuning = true
        } label: {
            headerLabel
        }
        .buttonStyle(.plain)
        #else
        headerLabel
        #endif
    }

    private var headerLabel: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Liked").font(.largeTitle).bold()
                if let countLine {
                    Text(countLine).font(.subheadline).foregroundStyle(.white.opacity(0.7))
                }
            }
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var countLine: String? {
        let total = appState.likedSongsStore.songs.count
        guard total > 0 else { return nil }
        return total == 1 ? "1 song" : "\(total) songs"
    }

    // MARK: - Content states

    @ViewBuilder
    private var content: some View {
        if appState.likedSongsStore.songs.isEmpty {
            staticLayout { emptyState }
        } else {
            songList
        }
    }

    private var songList: some View {
        List {
            // The heading is the first list row, so it scrolls up and away inline
            // with the songs rather than staying pinned above them.
            header
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
            ForEach(appState.likedSongsStore.songs) { snapshot in
                LikedSongRow(
                    snapshot: snapshot,
                    onSelect: { artwork in
                        selectedPlaycut = PlaycutSelection(playcut: snapshot.toPlaycut(), artwork: artwork)
                    },
                    onUnlike: { unlike(snapshot) }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        unlike(snapshot)
                    } label: {
                        Label("Unlike", systemImage: "heart.slash.fill")
                    }
                    .tint(LikeHeartButton.likeColor)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart").font(.system(size: 44))
            Text("Show some love").font(.headline)
            Text("Tap the heart on a song you love.")
                .font(.subheadline).foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    /// Removes the song from the store (heart-off and swipe share this path)
    /// and records the toggle. The event carries no artist or song identity —
    /// only lifecycle strings and the post-toggle size bucket.
    private func unlike(_ snapshot: LikedSongSnapshot) {
        withAnimation {
            appState.likedSongsStore.unlike(snapshot)
        }
        StructuredPostHogAnalytics.shared.capture(SongLikeToggled(
            action: "unlike",
            surface: "liked_tab",
            totalBucket: appState.likedSongsStore.totalBucket
        ))
    }
}

#Preview {
    LikedTabView()
        .environment(Singletonia.shared)
        .background(WXYCBackground())
}
