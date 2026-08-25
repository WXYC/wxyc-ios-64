//
//  WidgetStateService.swift
//  AppServices
//
//  Centralized service for managing widget state.
//  Observes playback state and playlist updates to keep widgets synchronized.
//
//  Created by Jake Bromberg on 01/02/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if canImport(WidgetKit)
import AppIntents
import Caching
import Core
import PlaybackCore
import Playlist
import WidgetKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Centralized service for managing widget state.
///
/// This service observes:
/// - Playback state changes from a `PlaybackController`
/// - Playlist updates from `PlaylistService`
/// - App termination to clear playback state
///
/// When changes occur, it:
/// - Updates the `isPlaying` key in `UserDefaults.wxyc`
/// - Reloads all widget timelines, but only when WidgetKit won't charge the
///   reload against the widget's scarce daily budget (see
///   ``reloadsAreExemptFromBudget``)
@MainActor
public final class WidgetStateService {
    private let playbackController: any PlaybackController
    private let playlistService: PlaylistService
    private let relevanceUpdater: any WidgetRelevanceUpdating
    private let reloader: any WidgetReloading
    private var isForegrounded = false
    private var playbackObservationTask: Task<Void, Never>?
    private var playlistObservationTask: Task<Void, Never>?
    private var appTerminationObservation: NSObjectProtocol?

    public init(
        playbackController: any PlaybackController,
        playlistService: PlaylistService,
        relevanceUpdater: any WidgetRelevanceUpdating = SystemWidgetRelevanceUpdater(),
        reloader: any WidgetReloading = SystemWidgetReloader()
    ) {
        self.playbackController = playbackController
        self.playlistService = playlistService
        self.relevanceUpdater = relevanceUpdater
        self.reloader = reloader

        // Listen for app termination to clear playback state
        #if canImport(UIKit) && !os(watchOS)
        appTerminationObservation = NotificationCenter.default
            .addMainActorObserver(of: UIApplication.shared, for: ApplicationWillTerminateMessage.self) { _ in
                self.clearPlaybackState()
            }
        #elseif canImport(AppKit)
        appTerminationObservation = NotificationCenter.default
            .addMainActorObserver(of: NSApplication.shared, for: ApplicationWillTerminateMessage.self) { _ in
                self.clearPlaybackState()
            }
        #endif

        // Clear stale playback state from previous app session.
        // The app wasn't playing when it was terminated, so reset to false.
        clearPlaybackState()

        // Clear stale relevance from previous session
        Task { await self.updateWidgetRelevance(isActive: false) }
    }

    deinit {
        playbackObservationTask?.cancel()
        playlistObservationTask?.cancel()
        // appTerminationObservation is automatically cleaned up on deallocation (iOS 18.6+)
    }

    // MARK: - Lifecycle

    /// Start observing playback and playlist updates.
    /// Call this when the app becomes active.
    public func start() {
        startObservingPlaybackState()
        startObservingPlaylistUpdates()
    }

    // MARK: - Foreground State

    /// Update the foreground state.
    ///
    /// Foreground is one of the two conditions under which WidgetKit exempts a
    /// reload from the daily budget — see ``reloadsAreExemptFromBudget``.
    public func setForegrounded(_ foregrounded: Bool) {
        let wasForegrounded = isForegrounded
        isForegrounded = foregrounded

        // When returning to foreground, sync state and reload widgets
        if foregrounded && !wasForegrounded {
            syncPlaybackState()
            reloadWidgets()
        }
    }

    // MARK: - Private

    private func clearPlaybackState() {
        UserDefaults.wxyc.set(false, forKey: UserDefaults.isPlayingKey)
    }

    private func syncPlaybackState() {
        let isPlaying = playbackController.state.isActive
        UserDefaults.wxyc.set(isPlaying, forKey: UserDefaults.isPlayingKey)
    }

    /// Whether a reload issued right now would be free.
    ///
    /// WidgetKit exempts a reload from the daily budget while the containing
    /// app is in the foreground *or* holds an active audio session. Both
    /// describe a user who is present, which is exactly when the widget is
    /// worth updating — so the app takes every free reload and declines every
    /// budgeted one.
    ///
    /// The audio-session half matters most: a listener has the app alive in
    /// the background receiving live flowsheet updates, and before this the
    /// widget went stale for exactly that user.
    private var reloadsAreExemptFromBudget: Bool {
        isForegrounded || playbackController.state.isActive
    }

    private func reloadWidgets() {
        reloader.reloadAllTimelines()
    }

    private func updateWidgetRelevance(isActive: Bool) async {
        #if os(iOS)
        if isActive {
            let intent = NowPlayingWidgetIntent()
            let twoHoursFromNow = Date.now.addingTimeInterval(2 * 60 * 60)
            let relevance = RelevantContext.date(from: .now, to: twoHoursFromNow)
            let relevant = RelevantIntent(intent, widgetKind: "NowPlayingWidget", relevance: relevance)
            await relevanceUpdater.updateRelevantIntents([relevant])
        } else {
            await relevanceUpdater.updateRelevantIntents([])
        }
        #endif
    }

    private func startObservingPlaybackState() {
        playbackObservationTask?.cancel()

        playbackObservationTask = Task { [weak self] in
            guard let self else { return }

            let observations = Observations {
                self.playbackController.state.isActive
            }

            for await isActive in observations {
                guard !Task.isCancelled else { break }

                // Update UserDefaults
                UserDefaults.wxyc.set(isActive, forKey: UserDefaults.isPlayingKey)

                // Update Smart Stack relevance hints
                await self.updateWidgetRelevance(isActive: isActive)

                // Reload Control Center controls to update toggle state
                #if os(iOS)
                ControlCenter.shared.reloadAllControls()
                #endif

                if self.reloadsAreExemptFromBudget {
                    self.reloadWidgets()
                }
            }
        }
    }

    private func startObservingPlaylistUpdates() {
        playlistObservationTask?.cancel()

        playlistObservationTask = Task { [weak self] in
            guard let self else { return }

            for await _ in self.playlistService.updates() {
                guard !Task.isCancelled else { break }

                if self.reloadsAreExemptFromBudget {
                    self.reloadWidgets()
                }
            }
        }
    }
}
#endif
