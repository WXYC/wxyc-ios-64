//
//  AudioEnginePlayerProtocol.swift
//  Playback
//
//  Protocol for audio engine playback abstraction.
//
//  Created by Jake Bromberg on 01/07/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if !os(watchOS)

@preconcurrency import AVFoundation

/// Events emitted by an audio engine player
public enum AudioPlayerEvent: Sendable {
    /// Playback started
    case started
    /// Playback paused
    case paused
    /// Playback stopped
    case stopped
    /// An error occurred
    case error(Error)
    /// Player needs more buffers to continue
    case needsMoreBuffers
    /// Playback stalled due to buffer underrun
    case stalled
    /// Playback recovered from a stall
    case recoveredFromStall
}

/// Protocol for audio engine players, enabling dependency injection for testing
public protocol AudioEnginePlayerProtocol: AnyObject, Sendable {
    /// The current volume level (0.0 to 1.0)
    var volume: Float { get set }

    /// Whether the player is currently playing
    var isPlaying: Bool { get }

    /// Stream of player events
    var eventStream: AsyncStream<AudioPlayerEvent> { get }

    /// Creates a fresh stream of audio buffers from the render tap for visualization.
    /// Each call returns a new stream; the previous stream's continuation is finished.
    /// Only yields buffers when the tap is installed via `installRenderTap()`.
    func makeRenderTapStream() -> AsyncStream<AVAudioPCMBuffer>

    /// Start playback
    func play() throws

    /// Pause playback
    func pause()

    /// Stop playback and reset
    func stop()

    /// Schedule a buffer for playback
    func scheduleBuffer(_ buffer: AVAudioPCMBuffer)

    /// Schedule multiple buffers for playback in a single batch (more efficient than individual calls)
    func scheduleBuffers(_ buffers: [AVAudioPCMBuffer])

    /// Install the render tap for audio visualization. Call this when visualization is needed.
    /// The tap runs at ~60Hz and consumes CPU, so only install when actively displaying visualizations.
    func installRenderTap()

    /// Remove the render tap when visualization is no longer needed.
    func removeRenderTap()
}

#endif
