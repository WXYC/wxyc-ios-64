//
//  AudioPlayerProtocol.swift
//  Playback
//
//  Protocol for low-level audio player abstraction
//
//  Created by Jake Bromberg on 11/30/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
import AVFoundation

/// Protocol defining the low-level audio player interface
///
/// Players (RadioPlayer, MP3Streamer) implement this protocol.
/// They use `PlayerState` which does not include `.interrupted`
/// since that is a controller-level concern.
@MainActor
public protocol AudioPlayerProtocol: AnyObject {
    /// Whether the player is currently playing audio
    var isPlaying: Bool { get }

    /// The current player state
    ///
    /// Note: Uses `PlayerState` (not `PlaybackState`) because players
    /// don't handle system interruptions - that's a controller concern.
    var state: PlayerState { get }

    /// Start playing audio
    func play()

    /// Stop playback and reset stream
    func stop()

    /// Stream of player state changes
    var stateStream: AsyncStream<PlayerState> { get }
    
    /// Creates a fresh stream of audio buffers for visualization.
    /// Each call returns a new stream; the previous stream's continuation is finished.
    /// Should be buffered with .bufferingNewest(1) to avoid blocking audio thread.
    /// Only yields buffers when render tap is installed via `installRenderTap()`.
    func makeAudioBufferStream() -> AsyncStream<AVAudioPCMBuffer>

    /// Stream of internal player events (errors, stalls, recovery)
    var eventStream: AsyncStream<AudioPlayerInternalEvent> { get }

    /// Install the render tap for audio visualization.
    /// The tap runs at ~60Hz and consumes CPU, so only install when actively displaying visualizations.
    func installRenderTap()

    /// Remove the render tap when visualization is no longer needed.
    func removeRenderTap()
}

/// Internal events that can occur during playback
public enum AudioPlayerInternalEvent: Sendable {
    case error(Error)
    case stall
    case recovery
    /// The player has begun rendering audio for the first time this session.
    /// Emitted exactly once per successful start (not on stall/reconnect recovery),
    /// carrying the elapsed seconds from the play intent to first audio. The
    /// controller forwards this as a `PlaybackFirstAudioEvent` so success and
    /// failure are counted at the same layer (issue #513). Player-agnostic: any
    /// `AudioPlayerProtocol` implementation can emit it so the start-success rate
    /// is comparable across player types.
    case firstAudio(timeToAudio: TimeInterval)
}

// MARK: - Concurrency

// AVAudioPCMBuffer is not Sendable by default, but we need to pass it through AsyncStream
// for visualization. We treat it as Sendable since we transfer ownership to the stream
// and don't mutate it after yielding.
extension AVAudioPCMBuffer: @unchecked Sendable {}
