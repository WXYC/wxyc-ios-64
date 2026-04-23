//
//  ArtistDetailView.swift
//  WXYC
//
//  Detail view for a recommended artist pushed from WXYCRecommendsSection.
//  Fetches artist detail, preview, and bio from the semantic-index and
//  metadata services, reusing existing UI components throughout.
//
//  Created by Jake Bromberg on 04/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import Metadata
import MusicShareKit
import SemanticIndex
import SwiftUI
import WXUI

struct ArtistDetailView: View {
    let artist: RecommendedArtist

    @State private var detail: SemanticIndexArtistDetail?
    @State private var preview: SemanticIndexPreview?
    @State private var bio: String?
    @State private var isLoading = true
    @State private var expandedBio = false

    private let semanticService = SemanticIndexService()
    private let metadataService = PlaycutMetadataService(tokenProvider: MusicShareKit.authService)

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                artworkSection

                infoSection

                if let bio, !bio.isEmpty {
                    ArtistBioSection(bio: bio, expandedBio: $expandedBio)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.primary.opacity(0.1))
                        )
                }

                if let detail {
                    let links = ArtistStreamingLinks(detail: detail, preview: preview)
                    if links.hasLinks {
                        ArtistStreamingLinksSection(
                            links: links,
                            onServiceTapped: { service in
                                StructuredPostHogAnalytics.shared.capture(StreamingLinkTapped(
                                    service: service,
                                    artist: artist.name,
                                    album: ""
                                ))
                            }
                        )
                    }
                }

                if !isLoading {
                    WXYCRecommendsSection(artistName: artist.name)
                        .foregroundStyle(.white)
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal)
        }
        .scrollClipDisabled()
        .scrollContentBackground(.hidden)
        .overlaySheetScrollTracking()
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .foregroundStyle(.white)
        .onAppear {
            StructuredPostHogAnalytics.shared.capture(ArtistDetailViewPresented(artist: artist.name))
        }
        .task {
            await loadArtistData()
        }
    }

    // MARK: - Artwork

    private var artworkSection: some View {
        Group {
            if let artworkURL = preview?.artworkURL {
                AsyncImage(url: artworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(.rect(cornerRadius: 12))
                            .shadow(radius: 20, x: 0, y: 10)
                    default:
                        artworkPlaceholder
                    }
                }
            } else {
                artworkPlaceholder
            }
        }
        .frame(maxWidth: 280, maxHeight: 280)
        .padding(.top, 30)
    }

    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.ultraThinMaterial)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
            }
            .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Info

    private var infoSection: some View {
        VStack(spacing: 6) {
            Text(artist.name)
                .font(.title2)
                .bold()
                .multilineTextAlignment(.center)

            if let genre = artist.genre {
                GenreTagsView(tags: [genre])
            }

            if let trackName = preview?.trackName, let albumName = preview?.albumName {
                Text("\(trackName) — \(albumName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Data Loading

    private func loadArtistData() async {
        async let detailTask = semanticService.artistDetail(id: artist.id)
        async let previewTask = semanticService.preview(for: artist.id)

        let (fetchedDetail, fetchedPreview) = await (detailTask, previewTask)

        // Fetch bio if we got a Discogs artist ID
        var fetchedBio: String?
        if let discogsId = fetchedDetail?.discogsArtistId {
            fetchedBio = await fetchArtistBio(discogsArtistId: discogsId)
        }

        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.3)) {
                self.detail = fetchedDetail
                self.preview = fetchedPreview
                self.bio = fetchedBio
                self.isLoading = false
            }
        }
    }

    private func fetchArtistBio(discogsArtistId: Int) async -> String? {
        // Reuse the metadata service to fetch artist bio via the existing proxy
        let metadata = await metadataService.fetchArtistBio(discogsArtistId: discogsArtistId)
        return metadata
    }
}
