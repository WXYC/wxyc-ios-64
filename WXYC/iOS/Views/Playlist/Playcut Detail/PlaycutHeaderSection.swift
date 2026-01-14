//
//  PlaycutHeaderSection.swift
//  WXYC
//
//  Header section showing artwork and track info.
//
//  Created by Jake Bromberg on 12/06/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
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
                Text(playcut.songTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                
                Text(playcut.artistName)
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
