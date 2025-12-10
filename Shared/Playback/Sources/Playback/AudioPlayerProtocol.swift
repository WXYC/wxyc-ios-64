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
    
    /// Called when audio buffers are available for processing (visualization)
    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)? { get set }
    
    /// Called when player state changes
    
    /// Called when stream metadata is received
    var onMetadata: (([String: String]) -> Void)? { get set }
}

