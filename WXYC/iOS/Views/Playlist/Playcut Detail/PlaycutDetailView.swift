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
import Concerts
import LikedSongs
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

    @Environment(\.dismiss) private var dismiss
    @Environment(\.artworkService) private var artworkService
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.reviewRequestService) var reviewRequestService
    @Environment(\.upcomingShowResolver) private var upcomingShowResolver
    @Environment(Singletonia.self) private var appState

    /// The upcoming show for this playcut's artist, resolved synchronously from
    /// the embedded feed value (no network call). A DEBUG override may synthesize
    /// a mock; release reads the embed directly.
    private var upcomingShow: Concert? {
        upcomingShowResolver.upcomingShow(for: playcut)
    }

    private let metadataService = PlaycutMetadataService(tokenProvider: MusicShareKit.tokenProvider)
    
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
                    onArtworkTap: presentArtworkLightbox,
                    isLiked: {
                        appState.likedSongsStore.isLiked(
                            artistName: playcut.artistName,
                            songTitle: playcut.songTitle
                        )
                    },
                    onToggleLike: toggleLike
                )
                .padding(.top, 30)

                // Box Office ticket — shown when the played artist has an
                // upcoming Triangle-area show.
                if let upcomingShow {
                    BoxOfficeTicketView(
                        show: upcomingShow,
                        colors: appState.themeConfiguration.effectiveTicketColors
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                        .onAppear {
                            // Opening a real ticket retires the discovery CTA — the
                            // lesson has landed. Gate on the embedded feed value, not
                            // `upcomingShow`, so the DEBUG mock never retires it.
                            if playcut.upcomingShow != nil {
                                appState.ticketFeatureCTAPersistence.recordRealTicketSeen()
                            }
                        }
                }

                // Metadata section
                if isLoadingMetadata {
                    PlaycutLoadingSection()
                        .foregroundStyle(.white)
                } else if metadata.hasMetadataSectionContent {
                    PlaycutMetadataSection(metadata: metadata, expandedBio: $expandedBio)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.white)
                }

                // Critic reviews — attributed snippet cards (ADR 0012). Gated by
                // the CriticReviewsFeature runtime flag (PostHog in Release, on by
                // default in Debug/TestFlight) AND its own non-empty array,
                // independent of the metadata card's hasMetadataSectionContent.
                if CriticReviewsFeature.shouldShowReviews(
                    isEnabled: CriticReviewsFeature.isEnabled(featureFlagProvider: appState.featureFlagProvider),
                    hasReviews: metadata.album.hasCriticReviews
                ) {
                    ReviewsSection(
                        reviews: metadata.album.criticReviews ?? [],
                        onLinkTapped: { source in
                            StructuredPostHogAnalytics.shared.capture(ExternalLinkTapped(
                                service: source,
                                artist: playcut.artistName,
                                album: playcut.releaseTitle ?? ""
                            ))
                        }
                    )
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
        // The shared frosted backdrop — the app gradient behind a translucent
        // `.ultraThinMaterial`, like the pre-#373a7e17 overlay-sheet card that let
        // the wallpaper show through. Shared with `ConcertDetailView` via
        // `DetailPresentation` so the two covers stay in lockstep.
        .background { DetailPresentation.backdrop.ignoresSafeArea() }
        // The cover's own close affordance, replacing the sheet's drag-to-dismiss.
        // Applied before the lightbox overlay below, so an expanded lightbox covers
        // it. Pinned top-leading under the safe-area inset, like the concert
        // detail's back chevron.
        .overlay(alignment: .topLeading) { closeButton }
        .onAppear {
            StructuredPostHogAnalytics.shared.capture(PlaycutDetailViewPresented(
                artist: playcut.artistName,
                album: playcut.releaseTitle ?? ""
            ))
        }
        .task {
            await loadMetadata()
        }
        .animation(.easeInOut(duration: 0.3), value: upcomingShow)
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

    /// The cover's back / close control — the same frosted-circle chevron the
    /// concert detail uses, dismissing this `.fullScreenCover`.
    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            DetailPresentation.chromeGlyph("chevron.left")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private func loadMetadata() async {
        // Build inline metadata from the V2 flowsheet row when present.
        //
        // This field list must be kept in sync by hand with two other
        // enumerations of the same 12 inline fields: Playcut's CodingKeys/
        // init(from:) (Shared/Playlist/Sources/Playlist/PlaylistEntry.swift)
        // and Playcut.hasV2Metadata's OR-chain in the same file. There's no
        // compiler-enforced link — #685 itself patched one drift here
        // (artworkURL was missing from this construction).
        //
        // `criticReviews` below is NOT one of the 12 — like `artistId` and
        // `upcomingShow`, it's excluded from `hasV2Metadata`'s predicate (see
        // that doc comment) — but it still needs to ride through to
        // `AlbumMetadata` here so a terminal row's `ReviewsSection` renders
        // from feed data alone (#695).
        let inline = playcut.hasV2Metadata ? PlaycutMetadata(
            artist: ArtistMetadata(bio: playcut.artistBio, wikipediaURL: playcut.artistWikipediaURL),
            album: AlbumMetadata(
                label: playcut.labelName,
                releaseYear: playcut.releaseYear,
                discogsURL: playcut.discogsURL,
                genres: playcut.genres,
                styles: playcut.styles,
                artworkURL: playcut.artworkURL,
                criticReviews: playcut.criticReviews,
                // Like criticReviews above, discogsUnavailable isn't one of
                // the 12 hasV2Metadata fields (see that predicate's doc
                // comment) but still rides along here so the artwork-fetch
                // gate below can see it (#390).
                discogsUnavailable: playcut.discogsUnavailable,
                discogsUnavailableNote: playcut.discogsUnavailableNote
            ),
            streaming: StreamingLinks(
                spotifyURL: playcut.spotifyURL,
                appleMusicURL: playcut.appleMusicURL,
                youtubeMusicURL: playcut.youtubeMusicURL,
                bandcampURL: playcut.bandcampURL,
                soundcloudURL: playcut.soundcloudURL
            )
        ) : nil

        // Explicit branch on the row's server-side enrichment lifecycle
        // (#270), replacing the old `hasV2Metadata`-only heuristic at this
        // call site. `enrichedMatch`/`enrichedNoMatch`/`failedNoRetry` are
        // terminal — Backend has already finished (or given up on)
        // enrichment — so this branch renders straight from the inline V2
        // flowsheet fields and never calls `metadataService.fetchMetadata`:
        // no outbound `/proxy/metadata/album` request is possible on this
        // path. `pending`/`enriching` rows are still being enriched
        // server-side, and `nil` covers V1 rows, pre-Epic-C Backend deploys,
        // and feeds decoded before #280's `metadata_status` field existed —
        // both fall back to the existing metadata service, unchanged.
        let resolvedMetadata: PlaycutMetadata
        switch playcut.metadataStatus {
        case .enrichedMatch, .enrichedNoMatch, .failedNoRetry:
            resolvedMetadata = inline ?? .empty
        case .pending, .enriching, nil:
            resolvedMetadata = await metadataService.fetchMetadata(for: playcut, inline: inline)
        }

        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.3)) {
                self.metadata = resolvedMetadata
                self.isLoadingMetadata = false
            }
        }

        // If we still have no artwork and metadata provided an artwork URL, fetch it.
        // Skipped when the MD has flagged the release "Not on Discogs" (#390):
        // the URL, if present at all, is a preserved false match the flag
        // exists specifically to stop rendering — PlaycutHeaderSection falls
        // back to PlaceholderArtworkView whenever `artwork` stays nil.
        if artwork == nil,
           let artworkURL = resolvedMetadata.album.artworkURL,
           !resolvedMetadata.album.isDiscogsUnavailable {
            await loadArtwork(from: artworkURL)
        }
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

    /// Toggles the song like from the detail card's heart and records the
    /// toggle. The event carries no artist or song identity — only lifecycle
    /// strings and the post-toggle size bucket.
    private func toggleLike() {
        let liked = appState.likedSongsStore.toggle(playcut)
        StructuredPostHogAnalytics.shared.capture(SongLikeToggled(
            action: liked ? "like" : "unlike",
            surface: "detail",
            totalBucket: appState.likedSongsStore.totalBucket
        ))
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
    .environment(Singletonia.shared)
}
