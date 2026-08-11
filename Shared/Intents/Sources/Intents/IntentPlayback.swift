//
//  IntentPlayback.swift
//  Intents
//
//  Shared playback-start helpers for the WXYC playback intents. PlayWXYC,
//  ToggleWXYC, and (on iOS 27) PlayWXYCAudio all need to keep the intent's
//  perform() alive until the live stream actually connects, so iOS doesn't
//  suspend the app first. This centralizes the poll-until-isPlaying loop that
//  was previously copy-pasted into each intent, as well as the
//  prepare/capture/toggle/wait sequence ToggleWXYC and WidgetToggleWXYC both
//  need (#331).
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Logger
import Playback
import PlaybackCore

/// Shared helpers for the WXYC playback intents.
enum IntentPlayback {
    /// Prepares the audio session, starts playback for `reason`, then waits for the
    /// stream to begin (or `timeout` to elapse) — keeping the calling intent alive.
    ///
    /// - Parameters:
    ///   - controller: Playback-control surface; defaults to the shared
    ///     controller. Injectable for tests (#497) — `MockAudioPlayer`
    ///     (`PlaybackTestUtilities`) isn't importable from `WXYCIntentsTests`,
    ///     so tests substitute a fake `IntentPlaybackControlling` instead.
    /// - Returns: Whether playback actually started before `timeout` elapsed.
    ///   `PlayWXYC` and `PlayWXYCAudio` report a friendly dialog either way and
    ///   don't need this, but `PlayMediaIntentHandler` (#829) does: without it,
    ///   a dead network or exhausted backoff still answered `.success`, giving
    ///   the user no audio and no system error affordance. Marked
    ///   `@discardableResult` so those two callers don't need updating.
    @MainActor
    @discardableResult
    static func startAndAwait(
        reason: PlaybackReason,
        timeout: Duration = .seconds(10),
        controller: any IntentPlaybackControlling = AudioPlayerController.shared
    ) async -> Bool {
        Log(.info, "\(reason)")

        // Prepare audio session early to signal to iOS that audio playback is imminent
        controller.prepareForPlayback()

        controller.play(reason: reason)

        // Wait for playback to start before returning, keeping the intent alive
        // so iOS doesn't suspend the app before the stream connects
        return await awaitPlaybackStart(timeout: timeout, context: reason.description) { controller.isPlaying }
    }

    /// Polls `isPlaying` until it becomes true or `timeout` elapses.
    ///
    /// - Parameters:
    ///   - timeout: How long to wait before giving up.
    ///   - context: Log prefix identifying the calling intent (e.g. `"ToggleWXYC intent"`).
    ///   - isPlaying: Playback-state probe; defaults to the shared controller. Injectable for tests.
    /// - Returns: `true` if `isPlaying` became true before `timeout` elapsed, `false` otherwise.
    @MainActor
    @discardableResult
    static func awaitPlaybackStart(
        timeout: Duration,
        context: String,
        isPlaying: @MainActor () -> Bool = { AudioPlayerController.shared.isPlaying }
    ) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)

        while !isPlaying() {
            if ContinuousClock.now >= deadline {
                Log(.warning, "\(context): timeout waiting for playback to start")
                return false
            }
            try? await Task.sleep(for: .milliseconds(100))
        }

        Log(.info, "\(context): playback started")
        return true
    }

    /// Toggles playback for `reason`, preparing the audio session first and — if the
    /// toggle turned playback *on* — waiting for the stream to connect before
    /// returning. `ToggleWXYC` and `WidgetToggleWXYC` both need exactly this
    /// prepare/capture/toggle/wait sequence to keep their intent alive until the
    /// stream connects; this centralizes the perform() body that was previously
    /// copy-pasted between them.
    ///
    /// - Parameters:
    ///   - reason: The `PlaybackReason` passed to `toggle(reason:)`.
    ///   - context: Log prefix identifying the calling intent (e.g. `"ToggleWXYC intent"`).
    ///   - timeout: How long to wait for playback to start after toggling on.
    ///   - controller: Playback-control surface; defaults to the shared
    ///     controller. Injectable for tests (#497), the same seam
    ///     `startAndAwait` uses.
    @MainActor
    static func toggleAndAwait(
        reason: PlaybackReason,
        context: String,
        timeout: Duration = .seconds(10),
        controller: any IntentPlaybackControlling = AudioPlayerController.shared
    ) async {
        Log(.info, "\(context)")

        // Prepare audio session early to signal to iOS that audio playback is imminent
        controller.prepareForPlayback()

        // Must be the same predicate `toggle(reason:)` branches on, or this
        // mispredicts which way the toggle went. Reading `isPlaying` here
        // would report `false` for a start already in flight — the toggle
        // would stop it while this waited out the full timeout for audio that
        // is never coming.
        let wasRequested = controller.isPlaybackRequested
        controller.toggle(reason: reason)

        // If we toggled to play, wait for playback to start before returning
        // so iOS doesn't suspend the app before the stream connects
        if !wasRequested {
            await awaitPlaybackStart(timeout: timeout, context: context) { controller.isPlaying }
        }
    }
}
