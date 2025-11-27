//
//  PlaycutDetailSections.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Core
import WXUI

// MARK: - Header Section

struct PlaycutHeaderSection: View {
    let playcut: Playcut
    let artwork: UIImage?
    
    var body: some View {
        VStack(spacing: 16) {
            // Artwork
            Group {
                if let artwork = artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    PlaceholderArtworkView(
                        cornerRadius: 12,
                        shadowYOffset: 3
                    )
                    .aspectRatio(1, contentMode: .fit)
                }
            }
            .frame(maxWidth: 280, maxHeight: 280)
            .clipShape(RoundedRectangle(cornerRadius: 12))
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
        }
    }
}

// MARK: - Loading Section

struct PlaycutLoadingSection: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.primary)
            Text("Loading metadata...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.primary.opacity(0.1))
        )
    }
}

// MARK: - Metadata Section

struct PlaycutMetadataSection: View {
    let metadata: PlaycutMetadata
    @Binding var expandedBio: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Label and Year
            if metadata.label != nil || metadata.releaseYear != nil {
                HStack(spacing: 24) {
                    if let label = metadata.label {
                        MetadataItem(title: "Label", value: label)
                    }
                    if let year = metadata.releaseYear {
                        MetadataItem(title: "Year", value: String(year))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            
            // Artist Bio
            if let bio = metadata.artistBio, !bio.isEmpty {
                ArtistBioSection(bio: bio, expandedBio: $expandedBio)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.primary.opacity(0.1))
        )
    }
}

// MARK: - Artist Bio Section

struct ArtistBioSection: View {
    let bio: String
    @Binding var expandedBio: Bool
    @State private var isTruncated: Bool = false
    @State private var parsedBio: AttributedString?
    
    private let resolver: DiscogsEntityResolver = DiscogsAPIEntityResolver.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About the Artist")
                .font(.headline)
                .foregroundStyle(.primary)
            
            parsedBioText
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(expandedBio ? nil : 4)
                .background(
                    TruncationDetector(text: parsedBioText, lineLimit: 4, isTruncated: $isTruncated)
                )
            
            if isTruncated {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedBio.toggle()
                    }
                } label: {
                    Text(expandedBio ? "Show Less" : "Read More")
                        .font(.caption.smallCaps())
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                }
            }
        }
        .task {
            // Parse async with resolver to resolve artist IDs
            parsedBio = await DiscogsFormatter.parseToAttributedString(bio, resolver: resolver)
        }
    }
    
    private var parsedBioText: Text {
        if let parsedBio {
            return Text(parsedBio)
        } else {
            // Show synchronously parsed version while async resolves
            return DiscogsFormatter.parse(bio)
        }
    }
}

// MARK: - Truncation Detection

private struct TruncationDetector: View {
    let text: Text
    let lineLimit: Int
    @Binding var isTruncated: Bool
    
    var body: some View {
        GeometryReader { geometry in
            text
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    GeometryReader { fullTextGeometry in
                        Color.clear.onAppear {
                            checkTruncation(fullHeight: fullTextGeometry.size.height, availableWidth: geometry.size.width)
                        }
                        .onChange(of: fullTextGeometry.size) { _ in
                            checkTruncation(fullHeight: fullTextGeometry.size.height, availableWidth: geometry.size.width)
                        }
                    }
                )
                .hidden()
        }
        .hidden()
    }
    
    private func checkTruncation(fullHeight: CGFloat, availableWidth: CGFloat) {
        // Estimate line height based on body font
        let estimatedLineHeight: CGFloat = 20
        let maxCollapsedHeight = CGFloat(lineLimit) * estimatedLineHeight * 1.2 // 1.2 for line spacing
        isTruncated = fullHeight > maxCollapsedHeight
    }
}

// MARK: - Streaming Links Section

struct StreamingLinksSection: View {
    let metadata: PlaycutMetadata
    let isLoading: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Listen On")
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StreamingButton(
                    service: .spotify,
                    url: metadata.spotifyURL,
                    isLoading: isLoading
                )
                
                StreamingButton(
                    service: .appleMusic,
                    url: metadata.appleMusicURL,
                    isLoading: isLoading
                )
                
                StreamingButton(
                    service: .youtubeMusic,
                    url: metadata.youtubeMusicURL,
                    isLoading: isLoading
                )
                
                StreamingButton(
                    service: .bandcamp,
                    url: metadata.bandcampURL,
                    isLoading: isLoading
                )
                
                StreamingButton(
                    service: .soundcloud,
                    url: metadata.soundcloudURL,
                    isLoading: isLoading
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.primary.opacity(0.1))
        )
    }
}

// MARK: - External Links Section

struct ExternalLinksSection: View {
    let metadata: PlaycutMetadata
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("More Info")
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 12) {
                if let discogsURL = metadata.discogsURL {
                    ExternalLinkButton(
                        title: "Discogs",
                        imageName: "discogs",
                        url: discogsURL
                    )
                }
                
                if let wikipediaURL = metadata.wikipediaURL {
                    ExternalLinkButton(
                        title: "Wikipedia",
                        imageName: "wikipedia",
                        url: wikipediaURL
                    )
                }
            }
        }
        .tint(.primary)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.primary.opacity(0.1))
        )
    }
}

