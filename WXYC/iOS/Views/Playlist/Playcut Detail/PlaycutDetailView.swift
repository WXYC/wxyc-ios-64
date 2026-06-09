//
//  PlaycutDetailView.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Analytics
import AppIntents
import AppServices
import Artwork
import Core
import Metadata
import MusicShareKit
import Playlist
import SwiftUI
import UIKit
import WXUI

struct PlaycutDetailView: View {
    let playcut: Playcut
    @State private var artwork: UIImage?

    init(playcut: Playcut, artwork: UIImage?) {
        self.playcut = playcut
        self._artwork = State(initialValue: artwork)
    }

    @State private var metadata: PlaycutMetadata = .empty
    @State private var isLoadingMetadata = true
    @State private var expandedBio = false
    @State private var isLightboxActive = false
    @State private var showLightboxContainer = false
    @State private var hideHeaderArtwork = false
    @Namespace private var artworkNamespace

    @Environment(\.artworkService) private var artworkService
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.reviewRequestService) var reviewRequestService

    private let metadataService = PlaycutMetadataService(tokenProvider: MusicShareKit.authService)
    
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
                } else if metadata.hasMetadataSectionContent {
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
                            StructuredPostHogAnalytics.shared.capture(StreamingLinkTapped(
                                service: service.displayName,
                                artist: playcut.artistName,
                                album: playcut.releaseTitle ?? ""
                            ))
                            donateAddedSongIntent(service: service)
                        }
                    )
                    .foregroundStyle(.white)
                }
                
                // External links (Discogs, Wikipedia)
                if metadata.discogsURL != nil || metadata.wikipediaURL != nil {
                    ExternalLinksSection(
                        metadata: metadata,
                        onLinkTapped: { service in
                            StructuredPostHogAnalytics.shared.capture(ExternalLinkTapped(
                                service: service,
                                artist: playcut.artistName,
                                album: playcut.releaseTitle ?? ""
                            ))
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
        .overlaySheetScrollTracking()
        .onAppear {
            StructuredPostHogAnalytics.shared.capture(PlaycutDetailViewPresented(
                artist: playcut.artistName,
                album: playcut.releaseTitle ?? ""
            ))
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
        .overlaySheetLightboxActive(isLightboxActive)
    }
    
    private func loadMetadata() async {
        // Branch on the V2 row's enrichment state (#270). When status is one
        // of the three terminal states (`enrichedMatch`, `enrichedNoMatch`,
        // `failedNoRetry`), inline fields are authoritative and we render
        // directly — zero outbound `/proxy/metadata/album` calls. Otherwise
        // (`pending`, `enriching`, or `nil` on V1 / pre-Epic-C rows) we fall
        // back to the proxy fetch.
        let fetchedMetadata: PlaycutMetadata
        let source: PlaycutMetadataSource
        if let inline = PlaycutInlineMetadata.from(playcut) {
            fetchedMetadata = inline
            source = .inline
        } else {
            fetchedMetadata = await metadataService.fetchMetadata(for: playcut, inline: nil)
            source = .fallback
        }

        StructuredPostHogAnalytics.shared.capture(PlaycutMetadataResolved(
            source: source.rawValue,
            metadataStatus: playcut.metadataStatus?.rawValue ?? "absent"
        ))

        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.3)) {
                self.metadata = fetchedMetadata
                self.isLoadingMetadata = false
            }
        }

        // If we still have no artwork and metadata provided an artwork URL, fetch it
        if artwork == nil, let artworkURL = fetchedMetadata.album.artworkURL {
            await loadArtwork(from: artworkURL)
        }
    }

    private enum PlaycutMetadataSource: String {
        case inline
        case fallback
    }

    private func loadArtwork(from url: URL) async {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let image = UIImage(data: data) else {
                return
            }

            // Store in artwork service cache so playlist rows pick it up
            if let artworkService, let cgImage = image.cgImage {
                await artworkService.cacheExternalArtwork(cgImage, for: playcut)
            }

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.artwork = image
                }
            }
        } catch {
            // Artwork fetch is best-effort
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

    private func donateAddedSongIntent(service: MusicService) {
        let intent = AddedSongToLibrary(
            songTitle: playcut.songTitle,
            artistName: playcut.artistName,
            albumName: playcut.releaseTitle,
            streamingService: service.displayName,
            artwork: artwork
        )

        Task {
            try? await intent.donate()
        }

        reviewRequestService?.recordSongAddedToLibrary()
    }
}

// MARK: - Preview

#Preview {
    PlaycutDetailView(
        playcut: Playcut(
            id: 1,
            hour: 0,
            chronOrderID: 1,
            timeCreated: 0,
            songTitle: "Marilyn (feat. Micachu)",
            labelName: "Warp",
            artistName: "Mount Kimbie",
            releaseTitle: "Love What Survives"
        ),
        artwork: nil
    )
}
