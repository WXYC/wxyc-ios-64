//
//  RadioPlayer.swift
//  Playback
//
//  AVPlayer-based radio streaming player.
//
//  Created by Jake Bromberg on 12/01/17.
//  Copyright © 2017 WXYC. All rights reserved.
//

import Foundation
import AVFoundation
import MediaPlayer
import Logger
import Core
import Analytics
import PlaybackCore

@MainActor
@Observable
public final class RadioPlayer: Sendable {
    private let streamURL: URL
    private var rateObservation: (any NSObjectProtocol)?
    private var stallObservation: (any NSObjectProtocol)?
    private var timer: Core.Timer = Core.Timer.start()
    private let analytics: AnalyticsService?
    private let notificationCenter: NotificationCenter

    /// Whether this instance holds a live analytics sink. `internal`, not part
    /// of the public API — exposed so tests (`@testable import`) can assert
    /// that a controller-wrapped instance was constructed with `analytics:
    /// nil`, since the wrapping controller (`RadioPlayerController`,
    /// `AudioPlayerController`) is expected to be the sole emitter of
    /// playback analytics (#669).
    var hasAnalyticsSink: Bool { analytics != nil }

    // MARK: - State

    /// The current player state
    public private(set) var state: PlayerState = .idle {
        didSet {
            if state != oldValue {
                stateContinuation.yield(state)
            }
        }
    }

    /// Whether audio is currently playing
    public var isPlaying: Bool {
        state == .playing
    }

    // MARK: - Streams

    /// Stream of player state changes
    public let stateStream: AsyncStream<PlayerState>
    private let stateContinuation: AsyncStream<PlayerState>.Continuation
        
    /// Creates a fresh stream of audio buffers (always empty for AVPlayer-based RadioPlayer).
    public func makeAudioBufferStream() -> AsyncStream<AVAudioPCMBuffer> {
        AsyncStream { $0.finish() }
    }

    /// Stream of internal player events (stalls, recovery, errors)
    public let eventStream: AsyncStream<AudioPlayerInternalEvent>
    private let eventContinuation: AsyncStream<AudioPlayerInternalEvent>.Continuation

    // MARK: - Initialization

    // MARK: - Initialization

    /// - Parameter analytics: The analytics sink `play()` reports to. Defaults
    ///   to `nil` so a fresh `RadioPlayer()` never emits on its own — a
    ///   controller wrapping this player (`RadioPlayerController`,
    ///   `AudioPlayerController`) is expected to be the sole emitter of
    ///   playback analytics; passing a live sink here on top of that would
    ///   double-count every "play" (#669). Callers that genuinely want this
    ///   player to report its own analytics standalone may still pass one
    ///   explicitly.
    public convenience init(
        streamURL: URL = RadioStation.WXYC.streamURL,
        analytics: AnalyticsService? = nil
    ) {
        let asset = AVURLAsset(url: streamURL, options: Self.streamingAssetOptions)
        self.init(
            streamURL: streamURL,
            player: AVPlayer(playerItem: AVPlayerItem(asset: asset)),
            analytics: analytics,
            notificationCenter: .default
        )
    }

    init(
        streamURL: URL = RadioStation.WXYC.streamURL,
        player: PlayerProtocol,
        analytics: AnalyticsService? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        self.streamURL = streamURL
        self.player = player
        self.analytics = analytics
        self.notificationCenter = notificationCenter

        // Initialize state stream
        var stateContinuation: AsyncStream<PlayerState>.Continuation!
        self.stateStream = AsyncStream { continuation in
            stateContinuation = continuation
        }
        self.stateContinuation = stateContinuation

        // Initialize event stream
        var eventContinuation: AsyncStream<AudioPlayerInternalEvent>.Continuation!
        self.eventStream = AsyncStream { continuation in
            eventContinuation = continuation
        }
        self.eventContinuation = eventContinuation

        // Observe rate changes to track playing state
        self.rateObservation = notificationCenter.addMainActorObserver(
            of: player as? AVPlayer,
            for: RateDidChangeMessage.self
        ) { [weak self] message in
            guard let self else { return }
            Log(.info, category: .playback, "RadioPlayer did receive rate change message: \(message)")
            self.handleRateChange(rate: message.rate)
        }

        // Observe playback stalls
        self.stallObservation = notificationCenter.addMainActorObserver(
            for: PlaybackStalledMessage.self
        ) { [weak self] _ in
            guard let self else { return }
            Log(.error, category: .playback, "RadioPlayer playback stalled")
            self.handlePlaybackStalled()
        }
    }

    // MARK: - Notification Handlers

    private func handleRateChange(rate: Float) {
        let isPlaying = rate > 0
        if isPlaying {
            // Transition from loading/stalled to playing
            if state == .loading || state == .stalled {
                if state == .stalled {
                    eventContinuation.yield(.recovery)
                }
                state = .playing
            }
            // Temporarily removed Time to first Audio event until we define a proper event for it
            // or we could use a custom generic event if needed, but sticking to typed events is better.
            // For now, let's omit it or create a typed event if crucial.
            // Ignoring for this refactor to keep it clean.
        } else if state == .playing {
            // Stopped playing but we didn't request it - could be a stall
            // Don't transition here; wait for stall notification or explicit pause
        }
    }

    private func handlePlaybackStalled() {
        if state == .playing || state == .loading {
            state = .stalled
            eventContinuation.yield(.stall)
        }
    }

    // MARK: - Playback Control

    public func play() {
        if state == .playing {
            analytics?.capture(PlaybackStartedEvent(reason: "already playing (local)"))
            return
        }

        analytics?.capture(PlaybackStartedEvent(reason: "radioPlayer play"))
        timer = Timer.start()
        state = .loading
        self.player.play()
    }

    func pause() {
        state = .idle
        self.player.pause()
        self.resetStream()
    }

    // MARK: - Private

    private let player: PlayerProtocol

    private static let streamingAssetOptions: [String: Any] = [
        AVURLAssetAllowsConstrainedNetworkAccessKey: true,
        AVURLAssetAllowsExpensiveNetworkAccessKey: true,
    ]

    private func resetStream() {
        let asset = AVURLAsset(url: self.streamURL, options: Self.streamingAssetOptions)
        let playerItem = AVPlayerItem(asset: asset)
        self.player.replaceCurrentItem(with: playerItem)
    }
}
