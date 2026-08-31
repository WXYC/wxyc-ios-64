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
import Wallpaper
import WXUI

struct PlaycutDetailView: View {
    let playcut: Playcut
    @State private var artwork: PlatformImage?

    /// The artwork URL a download is already in flight for, so the two callers
    /// of ``loadArtworkIfNeeded()`` can't both start one. See that method.
    @State private var loadingArtworkURL: URL?

    init(playcut: Playcut, artwork: PlatformImage?) {
        self.playcut = playcut
        self._artwork = State(initialValue: artwork)
    }

    /// Both metadata sources, accumulated rather than overwritten, so the
    /// on-appear resolve and the enrichment repair can land in either order
    /// without either degrading the card (#812).
    @State private var resolution = PlaycutMetadataResolution()

    /// Bounds how long the streaming section is willing to say "still working".
    ///
    /// `canBeRepaired` is derived from the row-tap snapshot and never goes
    /// false, and the only other thing that settles the section is a repair
    /// actually arriving — so an offline device, a poll that fails for the
    /// card's lifetime, or a row Backend leaves stuck in `enriching` would
    /// leave it pending forever. Before #1018 the section settled wrongly;
    /// without this it would not settle at all, which is a worse failure.
    ///
    /// Sized off the enrichment path's own worst case rather than a feel: the
    /// CDC lane's cold non-library resolution runs 4-20s on prod, bounded by
    /// LML's 25s hard cap and Backend's 29s client abort, so a repair that has
    /// not landed by 45s is not coming on this card's watch.
    @State private var enrichmentWaitExpired = false
    @State private var expandedBio = false
    @State private var isLightboxActive = false
    @State private var showLightboxContainer = false
    @State private var hideHeaderArtwork = false
    @Namespace private var artworkNamespace

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.upcomingShowResolver) private var upcomingShowResolver
    @Environment(Singletonia.self) private var appState
    /// The interpolated theme snapshot, source of the ticket's palette. Reading it
    /// from the environment rather than off `ThemeConfiguration` is what keeps the
    /// ticket ink crossfading in step with the header during a picker swipe.
    @Environment(\.themeAppearance) private var appearance

    /// The upcoming show for this playcut's artist, resolved synchronously from
    /// the embedded feed value (no network call). A DEBUG override may synthesize
    /// a mock; release reads the embed directly.
    private var upcomingShow: Concert? {
        upcomingShowResolver.upcomingShow(for: playcut)
    }

    private let resolver = PlaycutMetadataResolver(
        service: PlaycutMetadataService(tokenProvider: MusicShareKit.tokenProvider)
    )

    /// What the card renders — both sources coalesced. See
    /// ``PlaycutMetadataResolution`` for the precedence rule.
    private var metadata: PlaycutMetadata { resolution.metadata }

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

                // Box Office ticket — shown when the played artist has an
                // upcoming Triangle-area show.
                if let upcomingShow {
                    BoxOfficeTicketView(
                        show: upcomingShow,
                        colors: appearance.ticketColors,
                        surface: "playcut_detail"
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
                if resolution.isLoading {
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
                                songTitle: playcut.songTitle,
                                artist: playcut.artistName,
                                album: playcut.releaseTitle ?? ""
                            ))
                        }
                    )
                    .foregroundStyle(.white)
                }

                // Streaming links
                if metadata.hasStreamingLinks || !resolution.isLoading {
                    StreamingLinksSection(
                        metadata: metadata,
                        // Not `resolution.isLoading`: that goes false the moment
                        // the on-appear resolve reports, including when it
                        // reports nothing because the row is still enriching
                        // server-side — which renders five "no link here" tiles
                        // over a repair that is still coming.
                        isLoading: resolution.isStreamingPending(
                            canBeRepaired: PlaycutMetadataResolver.shouldObserveEnrichment(for: playcut)
                                && !enrichmentWaitExpired
                        ),
                        onServiceTapped: { service in
                            StructuredPostHogAnalytics.shared.capture(StreamingLinkTapped(
                                service: service.displayName,
                                songTitle: playcut.songTitle,
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
                                songTitle: playcut.songTitle,
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
        // The song-like heart, pinned top-trailing under the same inset so it sits
        // parallel with the close chevron — a peer chrome control, matching the
        // concert detail's trailing share/calendar buttons.
        .overlay(alignment: .topTrailing) { likeButton }
        .onAppear {
            StructuredPostHogAnalytics.shared.capture(PlaycutDetailViewPresented(
                songTitle: playcut.songTitle,
                artist: playcut.artistName,
                album: playcut.releaseTitle ?? ""
            ))
        }
        .task {
            let resolved = await resolver.resolve(for: playcut)
            withAnimation(.easeInOut(duration: 0.3)) {
                resolution.recordInitial(resolved)
            }
            await loadArtworkIfNeeded()
        }
        // Repair path for a card opened during the ~2s window in which the feed
        // serves a real row that hasn't finished enriching (#812).
        //
        // Keying the resolve `.task` on `playcut.metadataStatus` would be dead
        // code: `playcut` is a value snapshot captured at row-tap time and
        // parked in `RootTabView`/`LikedTabView`'s `@State selectedPlaycut`,
        // which nothing writes to when the feed polls — and `PlaycutSelection`
        // is `Identifiable`/`Equatable` on `transitionID` alone, so even an
        // updated selection wouldn't re-present the cover. The fresh row has to
        // come from the store, not the parent.
        //
        // This task and the resolve above are unordered by design: they write
        // to different slots of `resolution`, which derives what to render from
        // both. A slow resolve returning after the repair therefore cannot
        // restore the pre-enrichment snapshot.
        //
        // Read off `appState` rather than `\.playlistService` because
        // `Singletonia` is the one dependency both presentation sites
        // explicitly re-inject into the cover's separate context. The guard is
        // `repairs`' own precondition too; checking it here as well is what
        // keeps a row that can never be repaired from opening a playlist
        // subscription and holding the polling loop alive for the cover's
        // lifetime.
        .task {
            guard PlaycutMetadataResolver.shouldObserveEnrichment(for: playcut) else { return }
            try? await Task.sleep(for: .seconds(45))
            enrichmentWaitExpired = true
        }
        .task {
            guard PlaycutMetadataResolver.shouldObserveEnrichment(for: playcut) else { return }
            let playlists = appState.playlistService.updates()
            for await repaired in resolver.repairs(for: playcut, playlists: playlists) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    resolution.recordRepair(repaired)
                }
                await loadArtworkIfNeeded()
            }
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

    /// The song-like heart in the cover's top-trailing chrome — the same shared
    /// ``LikeHeartButton`` (like-red fill, celebratory burst, a11y) the row and
    /// Liked tab use, in its `.chrome` frame so it matches the close chevron.
    /// Reads the store directly so a like toggled from the row while the cover is
    /// open stays in sync.
    private var likeButton: some View {
        LikeHeartButton(
            isLiked: appState.likedSongsStore.isLiked(
                artistName: playcut.artistName,
                songTitle: playcut.songTitle
            ),
            action: toggleLike,
            style: .chrome
        )
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    /// Fetches cover art once the coalesced metadata has an artwork URL and the
    /// card doesn't already have an image. Runs after both the initial resolve
    /// and any repair, since either can be the one that supplies the URL.
    ///
    /// Skipped when the MD has flagged the release "Not on Discogs" (#390): the
    /// URL, if present at all, is a preserved false match the flag exists
    /// specifically to stop rendering — PlaycutHeaderSection falls back to
    /// PlaceholderArtworkView whenever `artwork` stays nil.
    ///
    /// `artwork == nil` alone stopped being enough once there were two callers:
    /// it doesn't survive the suspension inside `loadArtwork`, so a repair
    /// landing while the initial resolve's download is in flight passes the
    /// same guard and starts a second download of the same URL — two transfers,
    /// two `cacheExternalArtwork` writes, two animated assignments. Latching the
    /// in-flight URL closes that, while still letting a repair that supplies a
    /// *different* URL supersede the one being fetched.
    ///
    /// The inline-vs-proxy decision, and the 12-field inline builder that feeds
    /// it, live in `PlaycutMetadataResolver` (`Metadata`) — that builder is one
    /// of three hand-synced enumerations of the same field list, alongside
    /// `Playcut`'s `CodingKeys`/`init(from:)` and `Playcut.hasV2Metadata`.
    private func loadArtworkIfNeeded() async {
        guard artwork == nil,
              let artworkURL = metadata.album.artworkURL,
              !metadata.album.isDiscogsUnavailable,
              loadingArtworkURL != artworkURL
        else { return }

        loadingArtworkURL = artworkURL
        await loadArtwork(from: artworkURL)
    }

    private func loadArtwork(from url: URL) async {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let image = PlatformImage(data: data) else {
                return
            }

            // Store in artwork service cache so playlist rows pick it up
            if let cgImage = image.cgImage {
                await appState.artworkService.cacheExternalArtwork(cgImage, for: playcut)
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
    /// toggle, including song/artist/album identity (2026-08-21 identity
    /// reversal, docs/plans/likes-identity-capture.md).
    private func toggleLike() {
        let liked = appState.likedSongsStore.toggle(playcut)
        StructuredPostHogAnalytics.shared.capture(SongLikeToggled(
            fields: LikeAnalyticsFields.make(from: playcut, liked: liked),
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

        appState.reviewRequestService.recordSongAddedToLibrary()
    }
}

// MARK: - Preview

#Preview {
    // Built through `Playcut.init` rather than `Playcut.stub()`: the app target
    // doesn't link `PlaylistTesting`. See `PreviewFixtures` for why, and
    // `docs/test-fixtures.md` for the canonical values used here.
    PlaycutDetailView(
        playcut: Playcut(
            id: 1,
            hour: 0,
            chronOrderID: 1,
            timeCreated: 0,
            songTitle: "la paradoja",
            labelName: "Sonamos",
            artistName: "Juana Molina",
            releaseTitle: "DOGA"
        ),
        artwork: nil
    )
    .environment(Singletonia.shared)
}
