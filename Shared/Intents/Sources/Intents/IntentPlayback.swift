//
//  IntentPlayback.swift
//  Intents
//
//  Shared playback-start helpers for the WXYC playback intents. PlayWXYC,
//  ToggleWXYC, and (on iOS 27) PlayWXYCAudio all need to keep the intent's
//  perform() alive until the live stream actually connects, so iOS doesn't
//  suspend the app first. This centralizes the poll-until-isPlaying loop that
//  was previously copy-pasted into each intent.
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
    @MainActor
    static func startAndAwait(reason: PlaybackReason, timeout: Duration = .seconds(10)) async {
        Log(.info, "\(reason)")

        // Prepare audio session early to signal to iOS that audio playback is imminent
        AudioPlayerController.shared.prepareForPlayback()

        AudioPlayerController.shared.play(reason: reason)

        // Wait for playback to start before returning, keeping the intent alive
        // so iOS doesn't suspend the app before the stream connects
        await awaitPlaybackStart(timeout: timeout, context: reason.description)
    }

    /// Polls `isPlaying` until it becomes true or `timeout` elapses.
    ///
    /// - Parameters:
    ///   - timeout: How long to wait before giving up.
    ///   - context: Log prefix identifying the calling intent (e.g. `"ToggleWXYC intent"`).
    ///   - isPlaying: Playback-state probe; defaults to the shared controller. Injectable for tests.
    @MainActor
    static func awaitPlaybackStart(
        timeout: Duration,
        context: String,
        isPlaying: @MainActor () -> Bool = { AudioPlayerController.shared.isPlaying }
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)

        while !isPlaying() {
            if ContinuousClock.now >= deadline {
                Log(.warning, "\(context): timeout waiting for playback to start")
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }

        Log(.info, "\(context): playback started")
    }
}
