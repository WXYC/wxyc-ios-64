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

struct MacPlaylistRowView: View {
    let playcut: Playcut
    let isSelected: Bool

    @State private var artwork: NSImage?
    @Environment(\.artworkService) private var artworkService

    var body: some View {
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
                    .lineLimit(1)
                Text(playcut.artistName)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                ClockView(timeCreated: playcut.timeCreated)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? .white.opacity(0.15) : .clear)
        )
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
