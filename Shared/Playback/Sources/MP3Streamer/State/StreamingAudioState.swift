//
//  StreamingAudioState.swift
//  Playback
//
//  State machine for streaming audio lifecycle.
//
//  Created by Jake Bromberg on 12/07/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation

/// Represents the current state of the audio streamer
public enum StreamingAudioState: Sendable, Equatable {
    /// Player is idle, not connected
    case idle

    /// Connecting to the audio stream
    case connecting

    /// Connected and buffering audio data
    case buffering(bufferedCount: Int, requiredCount: Int)

    /// Actively playing audio
    case playing

    /// Playback paused (buffering continues)
    case paused

    /// Was playing, but buffer underrun occurred
    case stalled
    
    /// Attempting to reconnect after disconnect
    case reconnecting

    /// An error occurred
    case error(Error)

    public static func == (lhs: StreamingAudioState, rhs: StreamingAudioState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.connecting, .connecting),
             (.playing, .playing),
             (.stalled, .stalled),
             (.reconnecting, .reconnecting),
             (.paused, .paused):
            return true
        case let (.buffering(lCount, lRequired), .buffering(rCount, rRequired)):
            return lCount == rCount && lRequired == rRequired
        case let (.error(lError), .error(rError)):
            return lError.localizedDescription == rError.localizedDescription
        default:
            return false
        }
    }
}

extension StreamingAudioState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .idle:
            return "idle"
        case .connecting:
            return "connecting"
        case .buffering(let buffered, let required):
            return "buffering(\(buffered)/\(required))"
        case .playing:
            return "playing"
        case .stalled:
            return "stalled"
        case .reconnecting:
            return "reconnecting"
        case .paused:
            return "paused"
        case .error(let error):
            return "error(\(error.localizedDescription))"
        }
    }
}
