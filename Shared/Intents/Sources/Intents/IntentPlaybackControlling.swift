//
//  IntentPlaybackControlling.swift
//  Intents
//
//  The playback-control surface IntentPlayback.startAndAwait(reason:),
//  toggleAndAwait(reason:context:), and stopAndPublish(reason:context:) need
//  from AudioPlayerController.shared: prepare the session, start, toggle or
//  stop playback, and report the playing / requested state. AudioPlayerController is a singleton the intents call
//  directly, and its own test double (MockAudioPlayer, in
//  PlaybackTestUtilities) isn't importable from WXYCIntentsTests because that
//  target isn't a product library. This narrow protocol is the seam tests
//  substitute a fake against instead, so PlayWXYCAudio.perform() (by way of
//  startAndAwait) can be exercised without driving a real audio session. See
//  #497.
//
//  Created by Jake Bromberg on 08/10/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Playback
import PlaybackCore

/// `AudioPlayerController` conforms via the extension below, which is what
/// `startAndAwait(reason:controller:)` defaults `controller` to; tests
/// substitute a fake that records calls and drives `isPlaying` directly.
@MainActor
protocol IntentPlaybackControlling {
    /// See `AudioPlayerController.prepareForPlayback()`.
    func prepareForPlayback()
    /// See `AudioPlayerController.play(reason:)`.
    func play(reason: PlaybackReason)
    /// See `AudioPlayerController.toggle(reason:)`.
    func toggle(reason: PlaybackReason)
    /// See `AudioPlayerController.stop(reason:)` — the stop that also closes
    /// the listen for the #663 duration series, subject to the
    /// one-event-per-listen predicate (#933). Deliberately not
    /// `tearDown(reason:)`: an intent is a listener decision and has to be
    /// reported as one. #939 is what taking the teardown cost the Siri pause.
    func stop(reason: PlaybackReason)
    /// See `AudioPlayerController.isPlaying`.
    var isPlaying: Bool { get }
    /// See `AudioPlayerController.isPlaybackRequested` — the predicate
    /// `toggle(reason:)` branches on, distinct from `isPlaying` for a start
    /// that is requested but not yet audible.
    var isPlaybackRequested: Bool { get }
}

extension AudioPlayerController: IntentPlaybackControlling { }
