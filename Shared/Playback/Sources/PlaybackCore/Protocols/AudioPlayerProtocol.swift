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
    
    /// Stream of audio buffers for visualization
    /// Should be buffered with .bufferingNewest(1) to avoid blocking audio thread
    /// Note: Only yields buffers when render tap is installed via `installRenderTap()`
    var audioBufferStream: AsyncStream<AVAudioPCMBuffer> { get }

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
}

// MARK: - Concurrency

// AVAudioPCMBuffer is not Sendable by default, but we need to pass it through AsyncStream
// for visualization. We treat it as Sendable since we transfer ownership to the stream
// and don't mutate it after yielding.
extension AVAudioPCMBuffer: @unchecked Sendable {}
