//
//  AVAudioStreamer+AudioPlayerProtocol.swift
//  AVAudioStreamer
//
//  Extension to conform AVAudioStreamer to AudioPlayerProtocol
//

import Foundation
import AVFoundation
import PlaybackCore

#if !os(watchOS)

// MARK: - AudioPlayerProtocol Conformance

extension AVAudioStreamer: AudioPlayerProtocol {

    /// Whether audio is currently playing
    public var isPlaying: Bool {
        streamingState == .playing
    }

    /// Stream of player state changes
    public var stateStream: AsyncStream<PlayerState> {
        stateStreamInternal
    }

    /// Stream of internal player events
    public var eventStream: AsyncStream<AudioPlayerInternalEvent> {
        eventStreamInternal
    }

    // play() and stop() are already implemented directly in AVAudioStreamer

    /// Install the render tap for audio visualization
    public func installRenderTap() {
        audioPlayer.installRenderTap()
    }

    /// Remove the render tap when visualization is no longer needed
    public func removeRenderTap() {
        audioPlayer.removeRenderTap()
    }
}

#endif // !os(watchOS)
