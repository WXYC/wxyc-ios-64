//
//  IntentPlaybackControlling.swift
//  Intents
//
//  The playback-control surface IntentPlayback.startAndAwait(reason:) needs
//  from AudioPlayerController.shared: prepare the session, start playback,
//  and report whether it's playing. AudioPlayerController is a singleton the
//  intents call directly, and its own test double (MockAudioPlayer, in
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
    /// See `AudioPlayerController.isPlaying`.
    var isPlaying: Bool { get }
}

extension AudioPlayerController: IntentPlaybackControlling { }
