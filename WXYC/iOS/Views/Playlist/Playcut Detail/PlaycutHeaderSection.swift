//
//  PlaycutHeaderSection.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import WXUI
import Playlist

struct PlaycutHeaderSection: View {
    let playcut: Playcut
    let artwork: UIImage?
    @Binding var isShowingLightbox: Bool
    let artworkNamespace: Namespace.ID
    let artworkGeometryID: String
    
    var body: some View {
        VStack {
            // Artwork
            Button {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    isShowingLightbox = true
                }
            } label: {
                if let artwork = artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(12)
                        .padding(.bottom, 16)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
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
            .matchedGeometryEffect(id: artworkGeometryID, in: artworkNamespace, isSource: !isShowingLightbox)
            .shadow(radius: 20, x: 0, y: 10)
            
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
