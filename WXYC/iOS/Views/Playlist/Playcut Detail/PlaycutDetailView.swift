//
//  PlaycutDetailView.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import UIKit
import WXUI
import PostHog
import Playlist
import Metadata

struct PlaycutDetailView: View {
    let playcut: Playcut
    let artwork: UIImage?
    
    @State private var metadata: PlaycutMetadata = .empty
    @State private var isLoadingMetadata = true
    @State private var expandedBio = false
    @State private var isLightboxActive = false
    @State private var showLightboxContainer = false
    @State private var hideHeaderArtwork = false
    @Namespace private var artworkNamespace
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    private let metadataService = PlaycutMetadataService()
    
    private var artworkGeometryID: String {
        "playcut-artwork-\(playcut.id)"
    }
    
    private let heroSpringResponse: Double = 0.45
    private let heroSpringAnimation = Animation.spring(response: 0.45, dampingFraction: 0.85)
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Artwork and basic info
                PlaycutHeaderSection(
                    playcut: playcut,
                    artwork: artwork,
                    isLightboxActive: $isLightboxActive,
                    hideArtwork: hideHeaderArtwork,
                    artworkNamespace: artworkNamespace,
                    artworkGeometryID: artworkGeometryID,
                    onArtworkTap: presentArtworkLightbox
                )
                .padding(.top, 30)
                
                // Metadata section
                if isLoadingMetadata {
                    PlaycutLoadingSection()
                        .foregroundStyle(.white)
                } else if metadata.label?.isEmpty == false || metadata.releaseYear != nil {
                    PlaycutMetadataSection(metadata: metadata, expandedBio: $expandedBio)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.white)
                }
                
                // Streaming links
                if metadata.hasStreamingLinks || !isLoadingMetadata {
                    StreamingLinksSection(
                        metadata: metadata,
                        isLoading: isLoadingMetadata,
                        onServiceTapped: { service in
                            PostHogSDK.shared.capture(
                                "streaming link tapped",
                                properties: [
                                    "service": service.name,
                                    "artist": playcut.artistName,
                                    "album": playcut.releaseTitle
                                ]
                            )
                        }
                    )
                    .foregroundStyle(.white)
                }
                
                // External links (Discogs, Wikipedia)
                if metadata.discogsURL != nil || metadata.wikipediaURL != nil {
                    ExternalLinksSection(
                        metadata: metadata,
                        onLinkTapped: { service in
                            PostHogSDK.shared.capture(
                                "external link tapped",
                                properties: [
                                    "service": service,
                                    "artist": playcut.artistName,
                                    "album": playcut.releaseTitle
                                ]
                            )
                        }
                    )
                    .foregroundStyle(.white)
                }
                
                Spacer(minLength: 40)
            }
            .padding(.horizontal)
        }
        .scrollClipDisabled()
        .scrollContentBackground(.hidden)
        .background(WXYCBackground())
        .onAppear {
            PostHogSDK.shared.capture(
                "playcut detail view presented",
                properties: [
                    "artist": playcut.artistName,
                    "album": playcut.releaseTitle
                ]
            )
        }
        .task {
            await loadMetadata()
        }
        .overlay {
            if showLightboxContainer, let artwork {
                ArtworkLightboxView(
                    image: artwork,
                    namespace: artworkNamespace,
                    geometryID: artworkGeometryID,
                    isActive: isLightboxActive,
                    cornerRadius: 12
                ) {
                    dismissArtworkLightbox()
                }
                .transition(.identity)
            }
        }
    }
    
    private func loadMetadata() async {
        let fetchedMetadata = await metadataService.fetchMetadata(for: playcut)
        
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.3)) {
                self.metadata = fetchedMetadata
                self.isLoadingMetadata = false
            }
        }
    }
    
    private func presentArtworkLightbox() {
        guard artwork != nil else { return }
        hideHeaderArtwork = true
        showLightboxContainer = true
        withAnimation(heroSpringAnimation) {
            isLightboxActive = true
        }
    }
    
    private func dismissArtworkLightbox() {
        withAnimation(heroSpringAnimation) {
            isLightboxActive = false
        }
        
        // Allow the matched geometry animation to complete before revealing the source.
        DispatchQueue.main.asyncAfter(deadline: .now() + heroSpringResponse) {
            if !isLightboxActive {
                hideHeaderArtwork = false
                showLightboxContainer = false
            }
        }
    }
}

// MARK: - Preview

#Preview {
    PlaycutDetailView(
        playcut: Playcut(
            id: 1,
            hour: 0,
            chronOrderID: 1,
            songTitle: "Marilyn (feat. Micachu)",
            labelName: "Warp",
            artistName: "Mount Kimbie",
            releaseTitle: "Love What Survives"
        ),
        artwork: nil
    )
}
