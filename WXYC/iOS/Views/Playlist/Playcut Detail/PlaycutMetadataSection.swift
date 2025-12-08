//
//  PlaycutMetadataSection.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Metadata
import Playlist

struct PlaycutMetadataSection: View {
    let metadata: PlaycutMetadata
    @Binding var expandedBio: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
        
            if metadata.label != nil || metadata.releaseYear != nil {
                // Label and Year
                Grid(alignment: .leadingFirstTextBaseline, verticalSpacing: 10) {
                    if let label = metadata.label {
                        GridRow {
                            MetadataLabel(title: "Label")
                            MetadataValue(value: label)
                        }
                    }
                    if let year = metadata.releaseYear {
                        GridRow {
                            MetadataLabel(title: "Year")
                            HStack {
                                MetadataValue(value: String(year))
                                Spacer()
                            }
                        }
                    }
                }
                
                // Artist Bio
                if let bio = metadata.artistBio, !bio.isEmpty {
                    ArtistBioSection(bio: bio, expandedBio: $expandedBio)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.primary.opacity(0.1))
        )
    }
}

#Preview {
    @Previewable @State var expandedBio = false
    @Previewable @State var isShowingLightbox = false
    @Namespace var previewNamespace
    
    let metadata = PlaycutMetadata(
        label: "We Release Whatever The Fuck We Want Okay?",
        releaseYear: 2025,
        discogsURL: nil,
        artistBio: nil,
        wikipediaURL: nil,
        spotifyURL: nil,
        appleMusicURL: nil,
        youtubeMusicURL: nil,
        bandcampURL: nil,
        soundcloudURL: nil
    )
    
    PlaycutLoadingSection()
    
    PlaycutHeaderSection(
        playcut: Playcut(
            id: 0,
            hour: 0,
            chronOrderID: 0,
            songTitle: "Pharoah's Dance",
            labelName: "Columbia",
            artistName: "Miles Davis",
            releaseTitle: "Bitches Brew"
        ),
        artwork: nil,
        isShowingLightbox: $isShowingLightbox,
        artworkNamespace: previewNamespace,
        artworkGeometryID: "preview-artwork"
    )
    
    PlaycutMetadataSection(
        metadata: metadata,
        expandedBio: $expandedBio
    )
    
    ExternalLinksSection(metadata: metadata)
}
