//
//  RadioPlayerAdapter.swift
//  Playback
//
//  Adapter to make RadioPlayer conform to AudioPlayerProtocol
//

import Foundation
import AVFoundation
import PlaybackCore

/// Adapter that wraps RadioPlayer to conform to AudioPlayerProtocol
@MainActor
public final class RadioPlayerAdapter: AudioPlayerProtocol {

    // MARK: - AudioPlayerProtocol

    public var isPlaying: Bool {
        radioPlayer.isPlaying
    }

    public private(set) var state: PlaybackState = .idle

    public let stateStream: AsyncStream<PlaybackState>
    public let audioBufferStream: AsyncStream<AVAudioPCMBuffer>
    public let eventStream: AsyncStream<AudioPlayerInternalEvent>

    // MARK: - Private Properties

    private let url: URL
    private let radioPlayer: RadioPlayer
    private let stateContinuation: AsyncStream<PlaybackState>.Continuation
    private let audioBufferContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation
    private let eventContinuation: AsyncStream<AudioPlayerInternalEvent>.Continuation

    // MARK: - Initialization

    public init(url: URL) {
        self.url = url
        self.radioPlayer = RadioPlayer()

        // Initialize streams
        var stateContinuation: AsyncStream<PlaybackState>.Continuation!
        self.stateStream = AsyncStream { continuation in
            stateContinuation = continuation
        }
        self.stateContinuation = stateContinuation

        var audioBufferContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation!
        self.audioBufferStream = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            audioBufferContinuation = continuation
        }
        self.audioBufferContinuation = audioBufferContinuation

        var eventContinuation: AsyncStream<AudioPlayerInternalEvent>.Continuation!
        self.eventStream = AsyncStream { continuation in
            eventContinuation = continuation
        }
        self.eventContinuation = eventContinuation
    }

    // MARK: - AudioPlayerProtocol Methods

    public func play() {
        radioPlayer.play()
        updateState(.playing)
    }

    public func stop() {
        radioPlayer.pause()
        updateState(.idle)
    }

    // MARK: - Private Methods

    private func updateState(_ newState: PlaybackState) {
        state = newState
        stateContinuation.yield(newState)
    }
}
