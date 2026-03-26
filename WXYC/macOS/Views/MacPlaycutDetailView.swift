//
//  MacPlaycutDetailView.swift
//  WXYC
//
//  Detail pane for the macOS NavigationSplitView, showing artwork, track
//  metadata, and streaming links for the selected playcut.
//
//  Created by Jake Bromberg on 03/26/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppKit
import Artwork
import Core
import Metadata
import Playlist
import SwiftUI
import WXUI

struct MacPlaycutDetailView: View {
    let playcut: Playcut

    @State private var artwork: NSImage?
    @State private var metadata: PlaycutMetadata = .empty
    @State private var isLoadingMetadata = true
    @Environment(\.artworkService) private var artworkService
    @Environment(\.openURL) private var openURL

    private let metadataService = PlaycutMetadataService()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                artworkSection
                trackInfoSection
                streamingLinksSection
            }
            .padding()
        }
        .task(id: playcut.id) {
            await loadArtwork()
            await loadMetadata()
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var artworkSection: some View {
        Group {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .clipShape(.rect(cornerRadius: 12))
        .shadow(radius: 8, y: 4)
        .frame(maxWidth: 300)
    }

    @ViewBuilder
    private var trackInfoSection: some View {
        VStack(spacing: 6) {
            Text(playcut.songTitle)
                .font(.title2)
                .bold()
            Text(playcut.artistName)
                .font(.title3)
                .foregroundStyle(.secondary)
            if let releaseTitle = playcut.releaseTitle {
                Text(releaseTitle)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            if let labelName = playcut.labelName {
                Text(labelName)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            ClockView(timeCreated: playcut.timeCreated)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var streamingLinksSection: some View {
        if metadata.hasStreamingLinks {
            VStack(spacing: 8) {
                Text("Listen on")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let url = metadata.spotifyURL {
                    streamingLinkButton(title: "Spotify", url: url)
                }
                if let url = metadata.appleMusicURL {
                    streamingLinkButton(title: "Apple Music", url: url)
                }
                if let url = metadata.youtubeMusicURL {
                    streamingLinkButton(title: "YouTube Music", url: url)
                }
                if let url = metadata.bandcampURL {
                    streamingLinkButton(title: "Bandcamp", url: url)
                }
                if let url = metadata.soundcloudURL {
                    streamingLinkButton(title: "SoundCloud", url: url)
                }
            }
            .padding(.top, 8)
        }
    }

    private func streamingLinkButton(title: String, url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            HStack {
                Text(title)
                    .bold()
                Spacer()
                Image(systemName: "arrow.up.right")
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(.quaternary, in: .rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data Loading

    private func loadArtwork() async {
        guard let artworkService else { return }
        do {
            let cgImage = try await artworkService.fetchArtwork(for: playcut)
            await MainActor.run {
                self.artwork = cgImage.toNSImage()
            }
        } catch {
            // No artwork available
        }
    }

    private func loadMetadata() async {
        do {
            let result = try await metadataService.fetchMetadata(for: playcut)
            await MainActor.run {
                withAnimation {
                    self.metadata = result
                    self.isLoadingMetadata = false
                }
            }
        } catch {
            await MainActor.run {
                self.isLoadingMetadata = false
            }
        }
    }
}
