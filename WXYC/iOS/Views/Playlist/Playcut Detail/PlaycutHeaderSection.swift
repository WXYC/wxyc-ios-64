//
//  PlaycutHeaderSection.swift
//  WXYC
//
//  Header section showing artwork and track info, with the song-like heart
//  beside the title. Store-agnostic: like state and the toggle arrive as a
//  closure pair from PlaycutDetailView, which owns the store access.
//
//  Created by Jake Bromberg on 12/06/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Metadata
import WXUI
import Playlist

struct PlaycutHeaderSection: View {
    let playcut: Playcut
    let artwork: UIImage?
    @Binding var isLightboxActive: Bool
    let hideArtwork: Bool
    let artworkNamespace: Namespace.ID
    let artworkGeometryID: String
    let onArtworkTap: () -> Void
    /// Whether the playcut's song is currently liked. A closure rather than a
    /// value so the heart re-renders when the store changes underneath (a like
    /// toggled from the row while the card is open stays in sync).
    let isLiked: () -> Bool
    /// Toggles the like. The parent owns the store call and the analytics.
    let onToggleLike: () -> Void

    var body: some View {
        VStack {
            // Artwork
            Button(action: onArtworkTap) {
                if let artwork = artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    PlaceholderArtworkView(
                        cornerRadius: 12,
                        shadowYOffset: 3
                    )
                    .aspectRatio(contentMode: .fit)
                }
            }
            .frame(maxWidth: 280, maxHeight: 280)
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel("Expand artwork")
            .accessibilityHint("Tap to view full-screen")
            .accessibilityAddTraits(.isButton)
            .opacity(hideArtwork ? 0 : 1)
            .matchedGeometryEffect(id: artworkGeometryID, in: artworkNamespace, isSource: !isLightboxActive)
            .shadow(radius: 20, x: 0, y: 10)
            .disabled(artwork == nil)
            .padding(.bottom, 16)
            
            // Song info
            VStack {
                // The heart sits beside the title (study verdict: the detail
                // card keeps its heart next to the song title in all cases).
                HStack(alignment: .center, spacing: 4) {
                    Text(playcut.songTitle)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)

                    LikeHeartButton(isLiked: isLiked(), action: onToggleLike)
                }

                Text(DiscogsMarkupParser.stripDisambiguationSuffix(from: playcut.artistName))
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                
                if let releaseTitle = playcut.releaseTitle {
                    Text(releaseTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .foregroundStyle(.white)
            .padding(.bottom)
        }
    }
}
