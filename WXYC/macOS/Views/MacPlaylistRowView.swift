//
//  MacPlaylistRowView.swift
//  WXYC
//
//  Compact playlist row for the macOS sidebar, showing artwork thumbnail,
//  song title, artist name, and time.
//
//  Created by Jake Bromberg on 03/26/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppKit
import Artwork
import Core
import Playlist
import SwiftUI
import Wallpaper

struct MacPlaylistRowView: View {
    let playcut: Playcut
    let isSelected: Bool

    @State private var artwork: NSImage?
    @Environment(\.artworkService) private var artworkService

    var body: some View {
        ZStack {
            BackgroundLayer(cornerRadius: 12)

            HStack(spacing: 10) {
                // Thumbnail
                Group {
                    if let artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle()
                            .fill(.white.opacity(0.1))
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(.rect(cornerRadius: 4))

                // Track info
                VStack(alignment: .leading, spacing: 2) {
                    Text(playcut.songTitle)
                        .bold()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(playcut.artistName)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    ClockView(timeCreated: playcut.timeCreated)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .clipShape(.rect(cornerRadius: 12))
        .contentShape(.rect)
        .task {
            await loadArtwork()
        }
    }

    private func loadArtwork() async {
        guard let artworkService else { return }
        do {
            let cgImage = try await artworkService.fetchArtwork(for: playcut)
            await MainActor.run {
                self.artwork = cgImage.toNSImage()
            }
        } catch {
            // No artwork available
        }
    }
}
