//
//  PlayerState.swift
//  PlaybackCore
//
//  State enum for low-level audio players (RadioPlayer, AVAudioStreamer).
//  Does not include .interrupted since that is a controller-level concern.
//

import Foundation

/// Represents the current state of a low-level audio player.
///
/// This enum is for players (RadioPlayer, AVAudioStreamer) which handle
/// stream connectivity and audio decoding. The `.interrupted` state is
/// intentionally omitted as it's a controller-level concern handled by
/// RadioPlayerController and AudioPlayerController.
///
/// - Note: There is no `paused` state because this is live HTTP MP3 streaming
///   where pause semantically equals stop (the stream cannot be resumed from
///   the same position).
public enum PlayerState: Equatable, Sendable {
    /// Player is idle and not active
    case idle

    /// Player is loading (connection established, buffering)
    case loading

    /// Audio is actively playing
    case playing

    /// Playback has stalled due to network issues
    /// Recovery will be attempted automatically with exponential backoff
    case stalled

    /// Playback encountered an error
    case error(PlaybackError)
}

// MARK: - Convenience Properties

extension PlayerState {
    /// Whether audio is currently playing
    public var isPlaying: Bool {
        self == .playing
    }

    /// Whether playback is in a loading state
    public var isLoading: Bool {
        self == .loading
    }

    /// Whether playback is stalled
    public var isStalled: Bool {
        self == .stalled
    }

    /// Whether playback is in an error state
    public var isError: Bool {
        if case .error = self { return true }
        return false
    }

    /// Whether playback is idle (not active)
    public var isIdle: Bool {
        self == .idle
    }

    /// Whether playback is active (playing, loading, or stalled)
    public var isActive: Bool {
        switch self {
        case .playing, .loading, .stalled:
            return true
        case .idle, .error:
            return false
        }
    }
}

// MARK: - Conversion to PlaybackState

extension PlayerState {
    /// Converts this player state to the corresponding controller PlaybackState
    public var asPlaybackState: PlaybackState {
        switch self {
        case .idle:
            return .idle
        case .loading:
            return .loading
        case .playing:
            return .playing
        case .stalled:
            return .stalled
        case .error(let error):
            return .error(error)
        }
    }
}

// MARK: - CustomStringConvertible

extension PlayerState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .idle:
            "idle"
        case .loading:
            "loading"
        case .playing:
            "playing"
        case .stalled:
            "stalled"
        case .error(let error):
            "error(\(error))"
        }
    }
}
