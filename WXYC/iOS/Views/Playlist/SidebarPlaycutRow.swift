//
//  SidebarPlaycutRow.swift
//  WXYC
//
//  Simplified playcut row for use in sidebar List context. Displays a thumbnail,
//  song title, artist name, and time in a compact horizontal layout suitable for
//  NavigationSplitView sidebars.
//
//  Created by Jake Bromberg on 04/09/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Artwork
import Playlist
import SwiftUI
import UIKit
import WXUI

struct SidebarPlaycutRow: View {
    let playcut: Playcut

    @State private var artwork: UIImage?
    @State private var isLoadingArtwork = true

    @Environment(\.artworkService) private var artworkService

    var body: some View {
        HStack(spacing: 10) {
            artworkThumbnail
                .frame(width: 44, height: 44)
                .clipShape(.rect(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(playcut.songTitle)
                    .bold()
                    .lineLimit(1)

                Text(playcut.artistName)
                    .lineLimit(1)

                ClockView(timeCreated: playcut.timeCreated)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.white)
        .task {
            await loadArtwork()
        }
    }

    @ViewBuilder
    private var artworkThumbnail: some View {
        if let artwork {
            Image(uiImage: artwork)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if isLoadingArtwork {
            RoundedRectangle(cornerRadius: 4)
                .fill(.primary.opacity(0.1))
        } else {
            PlaceholderArtworkView(cornerRadius: 4, shadowYOffset: 0)
        }
    }

    private func loadArtwork() async {
        guard let artworkService else {
            isLoadingArtwork = false
            return
        }
        do {
            let cgImage = try await artworkService.fetchArtwork(for: playcut)
            withAnimation(.easeInOut(duration: 0.25)) {
                self.artwork = cgImage.toUIImage()
                self.isLoadingArtwork = false
            }
        } catch {
            isLoadingArtwork = false
        }
    }
}

#Preview {
    List {
        SidebarPlaycutRow(
            playcut: Playcut(
                id: 1,
                hour: 1706544000000,
                chronOrderID: 1,
                timeCreated: 1706549400000,
                songTitle: "VI Scose Poise",
                labelName: "Warp",
                artistName: "Autechre",
                releaseTitle: "Confield"
            )
        )
    }
    .listStyle(.sidebar)
}
