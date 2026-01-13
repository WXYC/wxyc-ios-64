//
//  Singletonia.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/13/25.
//  Copyright © 2025 WXYC. All rights reserved.
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

        // Configure artwork cache to use screen-width scaled HEIF images
        ArtworkCacheConfiguration.targetWidth = screenWidth * UIScreen.main.scale

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
