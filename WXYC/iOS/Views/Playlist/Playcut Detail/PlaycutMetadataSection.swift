//
//  PlaycutMetadataSection.swift
//  WXYC
//
//  Detailed metadata section (label, catalog#, etc.).
//
//  Created by Jake Bromberg on 12/06/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Metadata
import Playlist

struct PlaycutMetadataSection: View {
    let metadata: PlaycutMetadata
    @Binding var expandedBio: Bool

    private var tags: [String] {
        (metadata.album.genres ?? []) + (metadata.album.styles ?? [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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

            // Genre/Style Tags
            if !tags.isEmpty {
                GenreTagsView(tags: tags)
            }

            // Artist Bio
            if let bio = metadata.artistBio, !bio.isEmpty {
                ArtistBioSection(bio: bio, bioTokens: metadata.artist.bioTokens, expandedBio: $expandedBio)
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
    @Previewable @Namespace var previewNamespace
    
    let metadata = PlaycutMetadata(
        artist: .empty,
        album: AlbumMetadata(
            label: "Warp",
            releaseYear: 2001,
            genres: ["Electronic"],
            styles: ["IDM", "Abstract"]
        ),
        streaming: .empty
    )
    
    PlaycutLoadingSection()
    
    PlaycutHeaderSection(
        playcut: Playcut(
            id: 0,
            hour: 0,
            chronOrderID: 0,
            timeCreated: 0,
            songTitle: "Pharoah's Dance",
            labelName: "Columbia",
            artistName: "Miles Davis",
            releaseTitle: "Bitches Brew"
        ),
        artwork: nil,
        isLightboxActive: $isShowingLightbox,
        hideArtwork: false,
        artworkNamespace: previewNamespace,
        artworkGeometryID: "preview-artwork",
        onArtworkTap: {}
    )
    
    PlaycutMetadataSection(
        metadata: metadata,
        expandedBio: $expandedBio
    )
    
    ExternalLinksSection(metadata: metadata)
}
