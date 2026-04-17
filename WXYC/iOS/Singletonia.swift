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
    private(set) var artworkService = MultisourceArtworkService()
    let widgetStateService: WidgetStateService
    let reviewRequestService = ReviewRequestService(minimumVersionForReview: "1.0")

    let themeConfiguration = ThemeConfiguration()
    let themePickerState = ThemePickerState()

    private var nowPlayingObservationTask: Task<Void, Never>?

    private init() {
        self.widgetStateService = WidgetStateService(
            playbackController: AudioPlayerController.shared,
            playlistService: playlistService
        )

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
                artworkService = .withDiscogsFallback(key: secrets.discogsApiKey, secret: secrets.discogsApiSecret)
                await artworkService.clearNegativeCache()
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
