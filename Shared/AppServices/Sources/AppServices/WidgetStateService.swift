//
//  WidgetStateService.swift
//  AppServices
//
//  Centralized service for managing widget state.
//  Observes playback state and playlist updates to keep widgets synchronized.
//

#if canImport(WidgetKit)
import Caching
import Core
import PlaybackCore
import Playlist
import WidgetKit
#if canImport(UIKit)
import UIKit
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
/// - Reloads all widget timelines (when in foreground to preserve budget)
@MainActor
public final class WidgetStateService {
    private let playbackController: any PlaybackController
    private let playlistService: PlaylistService
    private var isForegrounded = false
    private var playbackObservationTask: Task<Void, Never>?
    private var playlistObservationTask: Task<Void, Never>?
    private var appTerminationObservation: NSObjectProtocol?

    public init(playbackController: any PlaybackController, playlistService: PlaylistService) {
        self.playbackController = playbackController
        self.playlistService = playlistService

        // Listen for app termination to clear playback state
        #if canImport(UIKit) && !os(watchOS)
        appTerminationObservation = NotificationCenter.default
            .addMainActorObserver(of: UIApplication.shared, for: ApplicationWillTerminateMessage.self) { _ in
                self.clearPlaybackState()
            }
        #endif
        
        // Clear stale playback state from previous app session.
        // The app wasn't playing when it was terminated, so reset to false.
        clearPlaybackState()
    }

    deinit {
        playbackObservationTask?.cancel()
        playlistObservationTask?.cancel()
    }

    // MARK: - Lifecycle

    /// Start observing playback and playlist updates.
    /// Call this when the app becomes active.
    public func start() {
        startObservingPlaybackState()
        startObservingPlaylistUpdates()
    }

    /// Stop all observations.
    /// Call this when the service is no longer needed.
    public func stop() {
        playbackObservationTask?.cancel()
        playbackObservationTask = nil
        playlistObservationTask?.cancel()
        playlistObservationTask = nil
    }

    // MARK: - Foreground State

    /// Update the foreground state.
    /// Widget reloads only occur when foregrounded to preserve the daily budget.
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
        UserDefaults.wxyc.set(false, forKey: "isPlaying")
    }

    private func syncPlaybackState() {
        let isPlaying = playbackController.state.isActive
        UserDefaults.wxyc.set(isPlaying, forKey: "isPlaying")
    }

    private func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
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
                UserDefaults.wxyc.set(isActive, forKey: "isPlaying")

                // Reload Control Center controls to update toggle state
                #if os(iOS)
                ControlCenter.shared.reloadAllControls()
                #endif

                // Reload widgets (foreground reloads don't count against daily budget)
                if self.isForegrounded {
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

                // Only reload widgets when foregrounded to preserve daily budget
                if self.isForegrounded {
                    self.reloadWidgets()
                }
            }
        }
    }
}
#endif
