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

/// Controller that runs marketing demo sequences when enabled.
@MainActor
@Observable
final class MarketingModeController {
    /// Whether marketing mode is enabled (via launch argument). `#if DEBUG`-gated
    /// so `-marketing` can never activate in a Release build: `start()` below
    /// only touches release-compiled `Singletonia` members, but the storage/model
    /// layers those members read from (`Singletonia.likedStorage(isMarketing:)`,
    /// `marketingOnTourModel`, `marketingHeroConcertID`) are themselves DEBUG-only
    /// and fall back to real, live data in Release. Gating here — the single
    /// entry point — keeps that fallback from ever being reached, instead of
    /// relying on every downstream call site to remember it independently.
    static let isEnabled: Bool = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        let enabled = args.contains("-marketing")
        if enabled {
            Log(.info, category: .general, "Marketing mode enabled via launch argument")
        }
        return enabled
        #else
        false
        #endif
    }()

    /// Guards against a second overlapping sequence — e.g. a second `.onAppear`
    /// firing for the root content view (a re-layout, or a second window under
    /// Catalyst multi-window). `likedSongsStore.toggle(_:)` isn't idempotent, so
    /// two concurrent sequences would like-then-unlike the same track.
    private static var hasStarted = false

    /// Minimum total duration for the theme cycling sequence. Trimmed from the
    /// original 15s so the retuned storyboard's on-screen total stays ≤ ~25s once
    /// the On Tour / Liked / Station scenes are added below. The loop below also
    /// enforces a minimum of 2 cycles regardless of this duration, since a single
    /// far-flung swipe can itself take close to 6s.
    private let minimumDuration: Duration = .seconds(6)

    /// Minimum number of theme swaps the cycling loop guarantees, regardless of
    /// how long any individual cycle takes. Without this floor, a single cycle
    /// whose randomly-picked theme is several carousel steps away can itself
    /// exceed `minimumDuration`, collapsing the "signature visual" scene to just
    /// one swap instead of the "1–2 swaps" the storyboard documents.
    private let minimumCycleCount = 2

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
    ///     for the Liked-tab scene. Release-compiled — every member touched
    ///     here (`setMarketingRoute`, `likedSongsStore.toggle`,
    ///     `marketingHeroConcertID`, the seed-override restore) is
    ///     release-safe, so this method needs no `#if DEBUG` of its own. It's
    ///     provably unreachable outside a DEBUG `-marketing` launch anyway,
    ///     since `isEnabled` (below) is itself `#if DEBUG`-gated.
    func start(
        playbackController: any PlaybackController,
        pickerState: ThemePickerState,
        configuration: ThemeConfiguration,
        playlistService: PlaylistService?,
        appState: Singletonia
    ) {
        guard Self.isEnabled, !Self.hasStarted else { return }
        Self.hasStarted = true

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

            // Cycle through themes until minimum duration reached (and at least
            // `minimumCycleCount` cycles, regardless of duration — see
            // `shouldContinueThemeCycling`).
            while Self.shouldContinueThemeCycling(
                cycleCount: cycleCount,
                elapsed: ContinuousClock.now - startTime,
                minimumCycleCount: minimumCycleCount,
                minimumDuration: minimumDuration
            ) {
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
            // uses by hand. Polls specifically for a playcut, not just any
            // playlist entry: the "playlist loaded" wait above accepts a bare
            // sign-on marker, which would otherwise leave `playcuts` empty and
            // silently skip this scene if the recording starts right at DJ
            // sign-on before the first track is logged.
            Log(.info, category: .general, "Marketing mode: liking the on-air track")
            let likeWaitStart = ContinuousClock.now
            var playcutToLike: Playcut?
            while ContinuousClock.now - likeWaitStart < playlistWaitTimeout {
                let playlist = await appState.playlistService.currentPlaylistSnapshot()
                if let playcut = playlist.playcuts.first {
                    playcutToLike = playcut
                    break
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
            if let playcutToLike {
                _ = appState.likedSongsStore.toggle(playcutToLike)
            } else {
                Log(.warning, category: .general, "Marketing mode: no playcut available to like within timeout")
            }
            try? await Task.sleep(for: likeHoldDelay)

            // Scene: On Tour — month-grouped list + the "WXYC recommends" For
            // You shelf (the station-recommended tier `Singletonia` seeds under
            // `-marketing`), then open a poster-first concert detail via the
            // same `ConcertOpenMessage` path a real shared-show link uses.
            // `marketingHeroConcertID` is derived from the same fixture
            // `Singletonia` builds the `-marketing` On Tour model from (not a
            // hardcoded id), so it can't desync from a future edit to that
            // fixture; nil in Release (mirrors `marketingOnTourModel`).
            Log(.info, category: .general, "Marketing mode: routing to On Tour")
            appState.setMarketingRoute(.onTour)
            try? await Task.sleep(for: onTourListHoldDelay)

            if let heroConcertID = appState.marketingHeroConcertID {
                Log(.info, category: .general, "Marketing mode: opening a concert detail")
                NotificationCenter.default.post(ConcertOpenMessage(concertID: heroConcertID, source: .scheme), subject: nil)
                try? await Task.sleep(for: onTourDetailHoldDelay)

                // Explicitly dismiss the concert detail before switching tabs,
                // rather than relying on `OnTourTabView`'s dismiss hook and
                // `RootTabView`'s tab switch — both reacting to the same
                // `marketingRoute` write below — to happen in some particular
                // order. SwiftUI doesn't guarantee relative ordering between
                // `.onChange` handlers on different views, so this uses a
                // separate signal with an explicit gap instead.
                Log(.info, category: .general, "Marketing mode: closing the concert detail")
                appState.requestMarketingOnTourDetailDismissal()
                try? await Task.sleep(for: .milliseconds(400))
            }

            // Scene: Liked — the like seeded above is already in the in-memory
            // store, so the list is non-empty.
            Log(.info, category: .general, "Marketing mode: routing to Liked")
            appState.setMarketingRoute(.liked)
            try? await Task.sleep(for: likedHoldDelay)

            // Scene: Station — on-air banner + Request Line.
            Log(.info, category: .general, "Marketing mode: routing to Station")
            appState.setMarketingRoute(.station)
            try? await Task.sleep(for: stationHoldDelay)

            // Restore the For You seed knobs `Singletonia.init` overrode for
            // this recording, so they don't stick past this launch (see
            // `restoreForYouSeedOverridesAfterMarketingRecording()`).
            appState.restoreForYouSeedOverridesAfterMarketingRecording()

            Log(.info, category: .general, "Marketing mode: sequence complete")
        }
    }

    /// Theme IDs to always exclude from marketing mode random selection.
    private static let permanentlyExcludedThemeIDs: Set<String> = ["wxyc_1983"]

    /// Pure decision for the theme-cycling loop, factored out so it's
    /// unit-testable without an actual `ContinuousClock` or `ThemePickerState`.
    /// Continues while under the cycle-count floor OR the duration hasn't
    /// elapsed — i.e. both a minimum count and a minimum duration are enforced,
    /// not just whichever is checked first.
    static func shouldContinueThemeCycling(
        cycleCount: Int,
        elapsed: Duration,
        minimumCycleCount: Int,
        minimumDuration: Duration
    ) -> Bool {
        cycleCount < minimumCycleCount || elapsed < minimumDuration
    }

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
