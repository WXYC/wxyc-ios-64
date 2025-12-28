//
//  AudioPlayerProtocol.swift
//  StreamingAudioPlayer
//
//  Protocol for low-level audio player abstraction
//

import Foundation
import AVFoundation

/// Protocol defining the low-level audio player interface
///
/// Players (RadioPlayer, AVAudioStreamer) implement this protocol.
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
    var audioBufferStream: AsyncStream<AVAudioPCMBuffer> { get }

    /// Stream of internal player events (errors, stalls, recovery)
    var eventStream: AsyncStream<AudioPlayerInternalEvent> { get }
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
