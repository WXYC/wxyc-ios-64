//
//  Singletonia.swift
//  WXYC
//
//  Observable singleton holding shared app state.
//
//  Created by Jake Bromberg on 01/12/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppServices
import Artwork
import Caching
import Core
import Logger
import MusicShareKit
import Observation
import Playback
import Playlist
import SwiftUI
import Wallpaper

/// Shared app state for cross-scene access (main UI and CarPlay)
@MainActor
@Observable
final class Singletonia {
    static let shared = Singletonia()

    let nowPlayingInfoCenterManager: NowPlayingInfoCenterManager
    let playlistService = PlaylistService()
    let artworkService = MultisourceArtworkService()
    let artworkLoader: ArtworkLoader
    let widgetStateService: WidgetStateService
    let reviewRequestService = ReviewRequestService(minimumVersionForReview: "1.0")
    let spotlightDonationService = SpotlightDonationService(
        storage: UserDefaults.wxyc,
        indexer: CoreSpotlightIndexer()
    )
    let playcutHistoryStore = PlaycutHistoryStore()

    let themeConfiguration = ThemeConfiguration()
    let themePickerState = ThemePickerState()

    /// Show/retire state for the Box Office ticket discovery CTA. Held here — not
    /// per scene — because two sibling scenes share it: `PlaylistView` reads
    /// `shouldShow` and records the dismiss, while `PlaycutDetailView` records the
    /// real-ticket view that retires it. One instance keeps both on the same keys.
    let ticketFeatureCTAPersistence = TicketFeatureCTAPersistence()

    private var nowPlayingObservationTask: Task<Void, Never>?
    private var nowPlayingPlaybackStateTask: Task<Void, Never>?
    private var spotlightDonationTask: Task<Void, Never>?

    private init() {
        self.widgetStateService = WidgetStateService(
            playbackController: AudioPlayerController.shared,
            playlistService: playlistService
        )
        self.artworkLoader = ArtworkLoader(service: artworkService)

        let screenWidth = UIScreen.main.bounds.size.width
        nowPlayingInfoCenterManager = NowPlayingInfoCenterManager(
            boundsSize: CGSize(width: screenWidth, height: screenWidth)
        )

        // Configure artwork cache to use half-screen-width scaled HEIF images.
        // Artwork is displayed at ~40% of screen width in playlist rows, so half-screen
        // resolution is more than sufficient. This cuts per-image memory from ~5.5MB to ~1.4MB.
        ArtworkCacheConfiguration.targetWidth = screenWidth * UIScreen.main.scale / 2

        let nowPlayingService = NowPlayingService(
            playlistService: playlistService,
            artworkService: artworkService
        )
        startNowPlayingObservation(nowPlayingService: nowPlayingService)
        startNowPlayingPlaybackStateObservation()
        startSpotlightDonation()
        startPlaycutHistory()
    }

    private func startNowPlayingObservation(nowPlayingService: NowPlayingService) {
        nowPlayingObservationTask = Task { [weak self] in
            do {
                for try await item in nowPlayingService {
                    guard !Task.isCancelled else { break }
                    self?.nowPlayingInfoCenterManager.handleNowPlayingItem(item)
                }
            } catch {
                Log(.error, "NowPlaying observation error: \(error)")
            }
        }
    }

    /// Feeds the Spotlight content index on every playlist tick.
    ///
    /// Subscribes to `PlaylistService.updates()` (a multi-observer broadcast)
    /// rather than `NowPlayingService`. NowPlayingService would work too, but
    /// its iterator awaits `artworkService.fetchArtwork` for every yield —
    /// artwork the donation path never uses (Spotlight surfaces the URL, not
    /// the decoded image). Feeding from the playlist stream directly avoids
    /// a duplicate artwork-fetch pipeline on every tick.
    ///
    /// Per tick this observer runs BOTH donation paths: `donateCurrentPlaycut`
    /// for elevated-priority surfacing of the on-air track (deduped against
    /// the last donated playcut inside the actor so metadata re-broadcasts
    /// don't burn XPC), and `donateRecentPlaycuts` so a long-running
    /// foreground session — the case where the user never lets iOS run
    /// `BGAppRefresh` — still rebuilds the recent-50-row window. The batch
    /// path is watermark-idempotent so post-first-fetch ticks short-circuit
    /// at the `chronOrderID > watermark` filter.
    ///
    /// The service references are captured strongly here on purpose: the
    /// task's lifetime is bound to `Singletonia.shared` (a static let), so
    /// there is no cycle to break and `[weak self]` would be misleading.
    private func startSpotlightDonation() {
        spotlightDonationTask = Task { [spotlightDonationService, playlistService] in
            for await playlist in playlistService.updates() {
                guard !Task.isCancelled else { break }
                if let currentPlaycut = playlist.playcuts.first {
                    await spotlightDonationService.donateCurrentPlaycut(currentPlaycut)
                }
                await spotlightDonationService.donateRecentPlaycuts(playlist.playcuts)
            }
        }
    }

    /// Feeds the persistent playcut history on every playlist tick.
    ///
    /// The store owns its subscription loop (the `WidgetStateService.start()`
    /// precedent), so unlike the sibling observation tasks there is nothing
    /// long-lived to store or cancel here: this fire-and-forget task exists
    /// only because `start(observing:)` is actor-isolated and `init` cannot
    /// await it. The captures are intentionally strong — both services live
    /// as long as `Singletonia.shared`.
    private func startPlaycutHistory() {
        Task { [playcutHistoryStore, playlistService] in
            await playcutHistoryStore.start(observing: playlistService)
        }
    }

    /// Mirror AudioPlayerController.isPlaying into MPNowPlayingInfoCenter.
    ///
    /// Required so the system promotes WXYC to the active Now Playing app on
    /// macOS / Mac Catalyst — without an explicit playbackState, Control Center
    /// stays empty and media keys are routed to other apps.
    private func startNowPlayingPlaybackStateObservation() {
        nowPlayingPlaybackStateTask = Task { [weak self] in
            // Dedupe: Observations re-yields on every tracked-property change, but isPlaying
            // collapses several player states (loading, stalled, error) to one Bool, so most
            // transitions repeat the previous value. Each MPNowPlayingInfoCenter write is an
            // IPC round-trip to mediaserverd, so skipping no-ops matters.
            var last: Bool?
            let observations = Observations {
                AudioPlayerController.shared.isPlaying
            }

            for await isPlaying in observations {
                guard !Task.isCancelled else { break }
                guard isPlaying != last else { continue }
                last = isPlaying
                self?.nowPlayingInfoCenterManager.setPlaybackState(isPlaying: isPlaying)
            }
        }
    }

    /// Update the foreground state (called when scene phase changes)
    func setForegrounded(_ foregrounded: Bool) {
        widgetStateService.setForegrounded(foregrounded)
    }

    /// Start the widget state service to observe playback and playlist updates
    func startWidgetStateService() {
        widgetStateService.start()
    }

    // MARK: - Configuration

    /// Fetches secrets from the backend and upgrades services that depend on them.
    ///
    /// Call this early in the app lifecycle. The artwork service starts with cache + URL
    /// fetcher only; once secrets arrive with Discogs credentials, the Discogs API fallback
    /// is added to the fetcher chain. Requires device session auth.
    ///
    /// Retries with exponential backoff on failure because a transient timeout would
    /// otherwise leave the Discogs fallback disabled for the entire session, causing
    /// all artwork lookups to fail for v1 API entries (which have no inline artworkURL).
    func fetchConfiguration() async {
        let appConfiguration = AppConfiguration()
        let maxAttempts = 4
        var delay: Duration = .seconds(5)

        for attempt in 1...maxAttempts {
            guard let authService = MusicShareKit.authService,
                  let secrets = await appConfiguration.fetchSecrets(tokenProvider: authService) else {
                Log(.info, "Secrets fetch attempt \(attempt)/\(maxAttempts) failed")

                guard attempt < maxAttempts else {
                    Log(.warning, "No secrets available after \(maxAttempts) attempts — Discogs fallback disabled")
                    return
                }

                try? await Task.sleep(for: delay)
                delay *= 3
                continue
            }

            if !secrets.discogsApiKey.isEmpty, !secrets.discogsApiSecret.isEmpty {
                let discogs = DiscogsArtworkService(
                    key: secrets.discogsApiKey,
                    secret: secrets.discogsApiSecret
                )
                await artworkService.addFetcher(discogs)
                artworkLoader.retryFailures()
                Log(.info, "Artwork service upgraded with Discogs fallback (attempt \(attempt))")
            }
            return
        }
    }

    // MARK: - Review Request Tracking

    private var playbackObservationTask: Task<Void, Never>?
    private var requestSentObservationTask: Task<Void, Never>?

    /// Start observing playback state to track user engagement for review requests.
    func startReviewRequestTracking() {
        startObservingPlaybackState()
        startObservingRequestSent()
    }

    private func startObservingPlaybackState() {
        playbackObservationTask?.cancel()

        playbackObservationTask = Task { [weak self] in
            guard let self else { return }

            var wasPlaying = AudioPlayerController.shared.isPlaying

            let observations = Observations {
                AudioPlayerController.shared.isPlaying
            }

            for await isPlaying in observations {
                guard !Task.isCancelled else { break }

                // Track when playback starts (transition from not playing to playing)
                if isPlaying && !wasPlaying {
                    self.reviewRequestService.recordPlaybackStarted()
                }
                wasPlaying = isPlaying
            }
        }
    }

    private func startObservingRequestSent() {
        requestSentObservationTask?.cancel()

        requestSentObservationTask = Task { [weak self] in
            guard let self else { return }

            for await _ in NotificationCenter.default.messages(of: RequestServiceSubject.shared, for: RequestSentMessage.self) {
                guard !Task.isCancelled else { break }
                self.reviewRequestService.recordRequestSent()
            }
        }
    }
}
