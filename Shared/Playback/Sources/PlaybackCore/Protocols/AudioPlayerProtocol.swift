//
//  AudioPlayerProtocol.swift
//  StreamingAudioPlayer
//
//  Protocol for low-level audio player abstraction
//

import Foundation
import AVFoundation

/// Protocol defining the low-level audio player interface
@MainActor
public protocol AudioPlayerProtocol: AnyObject {
    /// Whether the player is currently playing audio
    var isPlaying: Bool { get }

    /// The current playback state
    var state: PlaybackState { get }

    /// Start playing audio
    func play()

    /// Stop playback and reset stream
    func stop()
    
    /// Stream of playback state changes
    var stateStream: AsyncStream<PlaybackState> { get }
    
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
