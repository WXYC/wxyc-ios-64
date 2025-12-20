//
//  AudioPlayerProtocol.swift
//  StreamingAudioPlayer
//
//  Protocol for low-level audio player abstraction
//

import Foundation
import AVFoundation

/// Represents the state of an audio player
public enum AudioPlayerPlaybackState: Sendable {
    case stopped
    case playing
    case paused
    case buffering
    case error
}

/// Protocol defining the low-level audio player interface
@MainActor
public protocol AudioPlayerProtocol: AnyObject {
    /// Whether the player is currently playing audio
    var isPlaying: Bool { get }
    
    /// The current playback state
    var state: AudioPlayerPlaybackState { get }
    
    /// The current stream URL being played
    var currentURL: URL? { get }
    
    /// Start playing audio from the given URL
    func play(url: URL)
    
    /// Pause playback (can be resumed)
    func pause()
    
    /// Resume playback after pause
    func resume()
    
    /// Stop playback completely
    func stop()
    
    /// Stream of playback state changes
    var stateStream: AsyncStream<AudioPlayerPlaybackState> { get }
    
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
