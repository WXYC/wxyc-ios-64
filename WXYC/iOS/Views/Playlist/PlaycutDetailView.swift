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

// MARK: - PlaycutDetailView

struct PlaycutDetailView: View {
    let playcut: Playcut
    let artwork: UIImage?
    
    @State private var metadata: PlaycutMetadata = .empty
    @State private var isLoadingMetadata = true
    @State private var expandedBio = false
    
    @Environment(\.dismiss) private var dismiss
    
    private let metadataService = PlaycutMetadataService()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Artwork and basic info
                    headerSection
                    
                    // Metadata section
                    if isLoadingMetadata {
                        loadingSection
                    } else {
                        metadataSection
                    }
                    
                    // Streaming links
                    if metadata.hasStreamingLinks || !isLoadingMetadata {
                        streamingLinksSection
                    }
                    
                    // External links (Discogs, Wikipedia)
                    if metadata.discogsURL != nil || metadata.wikipediaURL != nil {
                        externalLinksSection
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding()
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.1, green: 0.1, blue: 0.2),
                        Color(red: 0.05, green: 0.05, blue: 0.15)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
        }
        .task {
            await loadMetadata()
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            // Artwork
            Group {
                if let artwork = artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.1))
                        .overlay {
                            Image("logo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .padding(40)
                                .opacity(0.5)
                        }
                }
            }
            .frame(maxWidth: 280, maxHeight: 280)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 20, x: 0, y: 10)
            
            // Song info
            VStack(spacing: 8) {
                Text(playcut.songTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                
                Text(playcut.artistName)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                
                if let releaseTitle = playcut.releaseTitle {
                    Text(releaseTitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            }
        }
    }
    
    // MARK: - Loading Section
    
    private var loadingSection: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.white)
            Text("Loading metadata...")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(height: 80)
    }
    
    // MARK: - Metadata Section
    
    private var metadataSection: some View {
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
                artistBioSection(bio: bio)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.1))
        )
    }
    
    private func artistBioSection(bio: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About the Artist")
                .font(.headline)
                .foregroundStyle(.white)
            
            Text(bio)
                .font(.body)
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(expandedBio ? nil : 4)
            
            if bio.count > 200 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedBio.toggle()
                    }
                } label: {
                    Text(expandedBio ? "Show Less" : "Read More")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.indigo)
                }
            }
        }
    }
    
    // MARK: - Streaming Links Section
    
    private var streamingLinksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Listen On")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StreamingButton(
                    service: .spotify,
                    url: metadata.spotifyURL,
                    isLoading: isLoadingMetadata
                )
                
                StreamingButton(
                    service: .appleMusic,
                    url: metadata.appleMusicURL,
                    isLoading: isLoadingMetadata
                )
                
                StreamingButton(
                    service: .youtubeMusic,
                    url: metadata.youtubeMusicURL,
                    isLoading: isLoadingMetadata
                )
                
                StreamingButton(
                    service: .bandcamp,
                    url: metadata.bandcampURL,
                    isLoading: isLoadingMetadata
                )
                
                StreamingButton(
                    service: .soundcloud,
                    url: metadata.soundcloudURL,
                    isLoading: isLoadingMetadata
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.1))
        )
    }
    
    // MARK: - External Links Section
    
    private var externalLinksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("More Info")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 12) {
                if let discogsURL = metadata.discogsURL {
                    ExternalLinkButton(
                        title: "Discogs",
                        systemImage: "music.note.list",
                        url: discogsURL
                    )
                }
                
                if let wikipediaURL = metadata.wikipediaURL {
                    ExternalLinkButton(
                        title: "Wikipedia",
                        systemImage: "book.closed",
                        url: wikipediaURL
                    )
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.1))
        )
    }
    
    // MARK: - Data Loading
    
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

// MARK: - Metadata Item

private struct MetadataItem: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
            Text(value)
                .font(.body)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Streaming Service

enum StreamingService {
    case spotify
    case appleMusic
    case youtubeMusic
    case bandcamp
    case soundcloud
    
    var name: String {
        switch self {
        case .spotify: return "Spotify"
        case .appleMusic: return "Apple Music"
        case .youtubeMusic: return "YouTube Music"
        case .bandcamp: return "Bandcamp"
        case .soundcloud: return "SoundCloud"
        }
    }
    
    var iconName: String {
        switch self {
        case .spotify: return "spotify"
        case .appleMusic: return "applemusic"
        case .youtubeMusic: return "youtubemusic"
        case .bandcamp: return "bandcamp"
        case .soundcloud: return "soundcloud"
        }
    }
    
    var systemIcon: String {
        switch self {
        case .spotify: return "music.note"
        case .appleMusic: return "music.note"
        case .youtubeMusic: return "play.rectangle.fill"
        case .bandcamp: return "music.quarternote.3"
        case .soundcloud: return "waveform"
        }
    }
    
    var color: Color {
        switch self {
        case .spotify: return Color(red: 0.11, green: 0.73, blue: 0.33)
        case .appleMusic: return Color(red: 0.98, green: 0.18, blue: 0.33)
        case .youtubeMusic: return Color(red: 1.0, green: 0.0, blue: 0.0)
        case .bandcamp: return Color(red: 0.38, green: 0.76, blue: 0.87)
        case .soundcloud: return Color(red: 1.0, green: 0.33, blue: 0.0)
        }
    }
}

// MARK: - Streaming Button

private struct StreamingButton: View {
    let service: StreamingService
    let url: URL?
    let isLoading: Bool
    
    var body: some View {
        Group {
            if let url = url {
                Link(destination: url) {
                    buttonContent
                }
            } else {
                buttonContent
                    .opacity(isLoading ? 0.5 : 0.3)
            }
        }
    }
    
    private var buttonContent: some View {
        HStack(spacing: 8) {
            Image(systemName: service.systemIcon)
                .font(.body)
            Text(service.name)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(service.color.opacity(url != nil ? 1.0 : 0.3))
        )
    }
}

// MARK: - External Link Button

private struct ExternalLinkButton: View {
    let title: String
    let systemImage: String
    let url: URL
    
    var body: some View {
        Link(destination: url) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.body)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.2))
            )
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
            labelName: "Columbia",
            artistName: "Miles Davis",
            releaseTitle: "Kind of Blue"
        ),
        artwork: nil
    )
}

