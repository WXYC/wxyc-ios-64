//
//  MarketingMode.swift
//  WXYC
//
//  Provides automated UI sequences for marketing video recording.
//  When the app is launched with the -marketing argument, this controller
//  auto-plays music and cycles through wallpaper themes.
//
//  Created by Claude on 01/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Logger
import Playback
import PlaybackCore
import Playlist
import SwiftUI
import Wallpaper
import WXYCIntents

/// Which tab the marketing recording wants shown. Written by
/// `MarketingModeController` during a `-marketing` run; `RootTabView` maps it to
/// its private `Page`. Nil in every production launch (mirrors `pendingConcertLink`).
enum MarketingRoute: Sendable {
    case nowPlaying, onTour, liked, station
}

/// Controller that runs marketing demo sequences when enabled.
@MainActor
@Observable
final class MarketingModeController {
    /// Whether marketing mode is enabled (via launch argument).
    static let isEnabled: Bool = {
        let args = ProcessInfo.processInfo.arguments
        let enabled = args.contains("-marketing")
        if enabled {
            Log(.info, category: .general, "Marketing mode enabled via launch argument")
        }
        return enabled
    }()

    /// Minimum total duration for the theme cycling sequence. Trimmed from the
    /// original 15s so the retuned storyboard's on-screen total stays ≤ ~25s once
    /// the On Tour / Liked / Station scenes are added below.
    private let minimumDuration: Duration = .seconds(6)

    /// Time to wait for playlist to load before starting.
    private let playlistWaitTimeout: Duration = .seconds(10)

    /// Delay to hold on the loaded playlist before cycling themes.
    private let playlistHoldDelay: Duration = .seconds(2)

    /// Delay between theme picker cycles.
    private let cycleDelay: Duration = .seconds(3)

    /// Hold after liking the on-air track, to show the heart-burst celebration.
    private let likeHoldDelay: Duration = .seconds(3)

    /// Hold on the On Tour list (and its For You shelf) before opening a detail.
    private let onTourListHoldDelay: Duration = .seconds(2)

    /// Hold on the opened concert detail (poster, Where, About the Artist).
    private let onTourDetailHoldDelay: Duration = .seconds(4)

    /// Hold on the Liked tab.
    private let likedHoldDelay: Duration = .seconds(3)

    /// Hold on the Station tab.
    private let stationHoldDelay: Duration = .seconds(2)

    /// Number of themes available.
    private var themeCount: Int {
        ThemeRegistry.shared.themes.count
    }

    /// Starts the marketing sequence.
    /// - Parameters:
    ///   - playbackController: The playback controller to start audio.
    ///   - pickerState: The theme picker state to control.
    ///   - configuration: The theme configuration.
    ///   - playlistService: The playlist service to wait for loading.
    ///   - appState: Shared app state, used to drive tab routes and seed a like
    ///     for the Liked-tab scene. Release-compiled — only release-safe members
    ///     (`setMarketingRoute`, `likedSongsStore.toggle`) are touched here, so
    ///     this method needs no `#if DEBUG` even though it never runs outside a
    ///     `-marketing` launch (`isEnabled` short-circuits below).
    func start(
        playbackController: any PlaybackController,
        pickerState: ThemePickerState,
        configuration: ThemeConfiguration,
        playlistService: PlaylistService?,
        appState: Singletonia
    ) {
        guard Self.isEnabled else { return }

        Log(.info, category: .general, "Marketing mode: starting sequence")

        Task {
            // Start playback immediately
            Log(.info, category: .general, "Marketing mode: starting playback")
            try? playbackController.play(reason: .marketingMode)

            // Wait for playlist to load
            Log(.info, category: .general, "Marketing mode: waiting for playlist to load (timeout: \(playlistWaitTimeout))")
            if let playlistService {
                let loadStartTime = ContinuousClock.now
                var playlistLoaded = false

                // Poll for playlist entries
                while ContinuousClock.now - loadStartTime < playlistWaitTimeout {
                    let entries = await playlistService.currentEntryCount()
                    if entries > 0 {
                        Log(.info, category: .general, "Marketing mode: playlist loaded with \(entries) entries")
                        playlistLoaded = true
                        break
                    }
                    try? await Task.sleep(for: .milliseconds(200))
                }

                if !playlistLoaded {
                    Log(.warning, category: .general, "Marketing mode: playlist did not load within timeout, proceeding anyway")
                }
            }

            // Hold on the playlist for 2 seconds
            Log(.info, category: .general, "Marketing mode: holding on playlist for \(playlistHoldDelay)")
            try? await Task.sleep(for: playlistHoldDelay)

            Log(.info, category: .general, "Marketing mode: starting theme cycle loop, minimum duration = \(minimumDuration)")
            let startTime = ContinuousClock.now
            var cycleCount = 0
            var selectedThemeIDs: Set<String> = [configuration.selectedThemeID]

            // Cycle through themes until minimum duration reached
            while ContinuousClock.now - startTime < minimumDuration {
                cycleCount += 1
                let elapsed = ContinuousClock.now - startTime
                Log(.info, category: .general, "Marketing mode: cycle \(cycleCount) (elapsed: \(elapsed))")

                // Enter theme picker
                withAnimation(ThemePickerState.transitionAnimation) {
                    pickerState.enter(currentThemeID: configuration.selectedThemeID)
                }

                // Wait for picker to appear
                try? await Task.sleep(for: .milliseconds(500))

                // Swipe to random theme (excluding previously selected)
                await swipeToRandomTheme(pickerState: pickerState, excluding: selectedThemeIDs)
                selectedThemeIDs.insert(pickerState.centeredThemeID)

                // Wait a moment to show the theme
                try? await Task.sleep(for: .milliseconds(500))

                // Exit theme picker (confirm selection)
                Log(.info, category: .general, "Marketing mode: selecting theme \(pickerState.centeredThemeID)")
                withAnimation(ThemePickerState.transitionAnimation) {
                    pickerState.confirmSelection(to: configuration)
                    pickerState.exit()
                }

                // Wait between cycles
                try? await Task.sleep(for: cycleDelay)
            }

            Log(.info, category: .general, "Marketing mode: theme cycling complete after \(cycleCount) cycles")

            // Scene: like the on-air track, for the heart-burst celebration on
            // the flowsheet row. Routes through `likedSongsStore`, which under
            // `-marketing` is backed by an in-memory store (`Singletonia`), so
            // this never writes `liked-songs.json` on a simulator someone also
            // uses by hand.
            Log(.info, category: .general, "Marketing mode: liking the on-air track")
            let playlist = await appState.playlistService.fetchPlaylist()
            if let playcut = playlist.playcuts.first {
                _ = appState.likedSongsStore.toggle(playcut)
            }
            try? await Task.sleep(for: likeHoldDelay)

            // Scene: On Tour — month-grouped list + the "WXYC recommends" For
            // You shelf (the station-recommended tier `Singletonia` seeds under
            // `-marketing`), then open a poster-first concert detail via the
            // same `ConcertOpenMessage` path a real shared-show link uses.
            Log(.info, category: .general, "Marketing mode: routing to On Tour")
            appState.setMarketingRoute(.onTour)
            try? await Task.sleep(for: onTourListHoldDelay)

            Log(.info, category: .general, "Marketing mode: opening a concert detail")
            NotificationCenter.default.post(ConcertOpenMessage(concertID: 1, source: .scheme), subject: nil)
            try? await Task.sleep(for: onTourDetailHoldDelay)

            // Scene: Liked — the like seeded above is already in the in-memory
            // store, so the list is non-empty. Switching routes here also closes
            // the On Tour detail cover (see `OnTourTabView`'s DEBUG-only
            // dismiss hook), so the two don't race.
            Log(.info, category: .general, "Marketing mode: routing to Liked")
            appState.setMarketingRoute(.liked)
            try? await Task.sleep(for: likedHoldDelay)

            // Scene: Station — on-air banner + Request Line.
            Log(.info, category: .general, "Marketing mode: routing to Station")
            appState.setMarketingRoute(.station)
            try? await Task.sleep(for: stationHoldDelay)

            Log(.info, category: .general, "Marketing mode: sequence complete")
        }
    }

    /// Theme IDs to always exclude from marketing mode random selection.
    private static let permanentlyExcludedThemeIDs: Set<String> = ["wxyc_1983"]

    /// Swipes to a random theme by updating the carousel index.
    /// Excludes certain themes (like "WXYC 1983") and previously selected themes from selection.
    /// - Parameters:
    ///   - pickerState: The theme picker state to control.
    ///   - excluding: Additional theme IDs to exclude (previously selected themes).
    private func swipeToRandomTheme(pickerState: ThemePickerState, excluding: Set<String>) async {
        let themes = ThemeRegistry.shared.themes
        guard themes.count > 1 else { return }

        // Combine permanent exclusions with previously selected themes
        let allExcluded = Self.permanentlyExcludedThemeIDs.union(excluding)

        // Find valid target indices (exclude current and all excluded themes)
        let currentIndex = pickerState.carouselIndex
        let validIndices = themes.enumerated().compactMap { index, theme -> Int? in
            guard !allExcluded.contains(theme.id),
                  index != currentIndex else {
                return nil
            }
            return index
        }

        guard let targetIndex = validIndices.randomElement() else {
            Log(.warning, category: .general, "Marketing mode: no valid themes remaining, all have been selected")
            return
        }

        // Animate to the target
        let direction = targetIndex > currentIndex ? 1 : -1
        let steps = abs(targetIndex - currentIndex)

        for _ in 0..<steps {
            withAnimation(.spring(duration: 0.3)) {
                pickerState.carouselIndex += direction
                pickerState.updateCenteredTheme(forIndex: pickerState.carouselIndex)
            }
            try? await Task.sleep(for: .milliseconds(300))
        }
    }
}
