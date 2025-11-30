//
//  PlaycutDetailView.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Core
import UIKit
import WXUI
import PostHog

struct PlaycutDetailView: View {
    let playcut: Playcut
    let artwork: UIImage?
    
    @State private var metadata: PlaycutMetadata = .empty
    @State private var isLoadingMetadata = true
    @State private var expandedBio = false
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    private let metadataService = PlaycutMetadataService()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Artwork and basic info
                PlaycutHeaderSection(playcut: playcut, artwork: artwork)
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
                                properties: ["service": service.name]
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
                                properties: ["service": service]
                            )
                        }
                    )
                    .foregroundStyle(.white)
                }
                
                Spacer(minLength: 40)
            }
            .padding(.horizontal)
        }
        .scrollContentBackground(.hidden)
        .background(WXYCBackground())
        .onAppear {
            PostHogSDK.shared.capture("playcut detail view presented")
        }
        .task {
            await loadMetadata()
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
