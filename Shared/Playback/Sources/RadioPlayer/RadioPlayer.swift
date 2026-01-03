//
//  RadioPlayer.swift
//  WXYC
//
//  Created by Jake Bromberg on 12/1/17.
//  Copyright © 2017 wxyc.org. All rights reserved.
//

import Foundation
import AVFoundation
import MediaPlayer
import Logger
import Core
import PostHog
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
        
    /// Stream of audio buffers (not supported by AVPlayer-based RadioPlayer)
    public let audioBufferStream: AsyncStream<AVAudioPCMBuffer>

    /// Stream of internal player events (stalls, recovery, errors)
    public let eventStream: AsyncStream<AudioPlayerInternalEvent>
    private let eventContinuation: AsyncStream<AudioPlayerInternalEvent>.Continuation

    // MARK: - Initialization

    public convenience init(streamURL: URL = RadioStation.WXYC.streamURL) {
        self.init(
            streamURL: streamURL,
            player: AVPlayer(url: streamURL),
            analytics: PostHogAnalytics.shared,
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

        // Initialize audio buffer stream (empty - AVPlayer doesn't expose PCM buffers)
        self.audioBufferStream = AsyncStream { continuation in
            continuation.finish()
        }

        // Initialize event stream
        var eventContinuation: AsyncStream<AudioPlayerInternalEvent>.Continuation!
        self.eventStream = AsyncStream { continuation in
            eventContinuation = continuation
        }
        self.eventContinuation = eventContinuation

        // Observe rate changes to track playing state
        self.rateObservation = notificationCenter.addObserver(
            forName: AVPlayer.rateDidChangeNotification,
            object: player as? AVPlayer,
            queue: nil
        ) { [weak self] notification in
            guard let self else { return }
            Log(.info, "RadioPlayer did receive rate change notification", notification)
            Task { @MainActor [weak self] in
                guard let self else { return }
                let isPlaying = self.player.rate > 0
                if isPlaying {
                    // Transition from loading/stalled to playing
                    if self.state == .loading || self.state == .stalled {
                        if self.state == .stalled {
                            self.eventContinuation.yield(.recovery)
                        }
                        self.state = .playing
                    }
                    let timeToAudio = self.timer.duration()
                    self.analytics?.capture("Time to first Audio", properties: [
                        "timeToAudio": timeToAudio
                    ])
                } else if self.state == .playing {
                    // Stopped playing but we didn't request it - could be a stall
                    // Don't transition here; wait for stall notification or explicit pause
                }
            }
        }

        // Observe playback stalls
        self.stallObservation = notificationCenter.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let self else { return }
            Log(.error, "RadioPlayer playback stalled", notification)
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.state == .playing || self.state == .loading {
                    self.state = .stalled
                    self.eventContinuation.yield(.stall)
                }
            }
        }
    }

    // MARK: - Playback Control

    public func play() {
        if state == .playing {
            analytics?.capture("already playing (local)")
            return
        }

        analytics?.capture("radioPlayer play")
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

    private func resetStream() {
        let asset = AVURLAsset(url: self.streamURL)
        let playerItem = AVPlayerItem(asset: asset)
        self.player.replaceCurrentItem(with: playerItem)
    }
}
