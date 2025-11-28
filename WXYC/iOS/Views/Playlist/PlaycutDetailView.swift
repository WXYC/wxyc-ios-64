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
                // Close button
                HStack {
                    Spacer()
                        .frame(maxWidth: .infinity)
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(.thinMaterial)
                            .frame(maxWidth: 30)
                    }
                }
                
                // Artwork and basic info
                PlaycutHeaderSection(playcut: playcut, artwork: artwork)
                
                // Metadata section
                if isLoadingMetadata {
                    PlaycutLoadingSection()
                } else if metadata.label?.isEmpty == false || metadata.releaseYear != nil {
                    PlaycutMetadataSection(metadata: metadata, expandedBio: $expandedBio)
                }
                
                // Streaming links
                if metadata.hasStreamingLinks || !isLoadingMetadata {
                    StreamingLinksSection(metadata: metadata, isLoading: isLoadingMetadata)
                }
                
                // External links (Discogs, Wikipedia)
                if metadata.discogsURL != nil || metadata.wikipediaURL != nil {
                    ExternalLinksSection(metadata: metadata)
                }
                
                Spacer(minLength: 40)
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
        .background(WXYCBackground())
        .presentationBackground(.ultraThinMaterial)
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
            songTitle: "Blue in Green",
            labelName: "Columbia Columbia Columbia Columbia Columbia ",
            artistName: "Miles Davis",
            releaseTitle: "Kind of Blue"
        ),
        artwork: nil
    )
}
