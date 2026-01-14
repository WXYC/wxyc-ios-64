//
//  PlaybackState.swift
//  Playback
//
//  Unified state enum for playback controllers.
//  Replaces scattered boolean properties (isPlaying, isLoading, isStalled).
//
//  Created by Jake Bromberg on 12/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation

/// Represents the current state of a playback controller.
///
/// This enum provides a single source of truth for playback state,
/// replacing the previous scattered boolean properties.
///
/// - Note: There is no `paused` state because this is live HTTP MP3 streaming
///   where pause semantically equals stop (the stream cannot be resumed from
///   the same position).
public enum PlaybackState: Equatable, Sendable {
    /// Playback is idle and not active
    case idle

    /// Playback is loading (connection established, buffering)
    case loading

    /// Audio is actively playing
    case playing

    /// Playback has stalled due to network issues
    /// Recovery will be attempted automatically with exponential backoff
    case stalled

    /// Playback was interrupted by the system (e.g., phone call)
    case interrupted

    /// Playback encountered an error
    case error(PlaybackError)
}

/// Errors that can occur during playback.
public enum PlaybackError: Error, Equatable, Sendable {
    /// Failed to activate the audio session
    case audioSessionActivationFailed(String)

    /// Network connection failed
    case connectionFailed(String)

    /// Stream decoding failed
    case decodingFailed(String)

    /// Maximum reconnection attempts exceeded
    case maxReconnectAttemptsExceeded

    /// Unknown or unspecified error
    case unknown(String)
}

// MARK: - Convenience Properties

extension PlaybackState {
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

    /// Whether playback is interrupted
    public var isInterrupted: Bool {
        self == .interrupted
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
        case .idle, .interrupted, .error:
            return false
        }
    }
}

// MARK: - CustomStringConvertible

extension PlaybackState: CustomStringConvertible {
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
        case .interrupted:
            "interrupted"
        case .error(let error):
            "error(\(error))"
        }
    }
}

extension PlaybackError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .audioSessionActivationFailed(let message):
            "audioSessionActivationFailed: \(message)"
        case .connectionFailed(let message):
            "connectionFailed: \(message)"
        case .decodingFailed(let message):
            "decodingFailed: \(message)"
        case .maxReconnectAttemptsExceeded:
            "maxReconnectAttemptsExceeded"
        case .unknown(let message):
            "unknown: \(message)"
        }
    }
}
