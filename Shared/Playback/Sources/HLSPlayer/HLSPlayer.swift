//
//  HLSPlayer.swift
//  HLSPlayerModule
//
//  AVPlayer-based HLS streaming player with time-shifting support.
//  Conforms to both AudioPlayerProtocol and TimeShiftablePlayer, enabling
//  listeners to seek backwards within a live HLS stream.
//
//  Created by Jake Bromberg on 03/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import AVFoundation
import CoreMedia
import Logger
import Core
import Analytics
import PlaybackCore

/// The number of seconds within which the player is considered "at the live edge."
/// Two HLS segments at 6 seconds each = 12 seconds.
private let liveEdgeThresholdSeconds: TimeInterval = 12

/// The maximum lookback window in seconds (1 hour).
private let maxLookbackCap: TimeInterval = 3600

/// The interval between time position stream updates.
private let timePositionUpdateInterval: Duration = .milliseconds(500)

@MainActor
@Observable
public final class HLSPlayer: Sendable {
    private let player: any HLSAVPlayerProtocol
    private let analytics: AnalyticsService?
    private let notificationCenter: NotificationCenter
    private var rateObservation: (any NSObjectProtocol)?
    private var stallObservation: (any NSObjectProtocol)?
    private var failureObservation: (any NSObjectProtocol)?
    private var timePositionTask: Task<Void, Never>?

    // MARK: - State

    public private(set) var state: PlayerState = .idle {
        didSet {
            if state != oldValue {
                stateContinuation.yield(state)
                if state == .playing {
                    startTimePositionUpdates()
                } else if state == .idle {
                    stopTimePositionUpdates()
                }
            }
        }
    }

    public var isPlaying: Bool { state == .playing }

    // MARK: - Time-Shift State

    public private(set) var secondsBehindLive: TimeInterval = 0

    public var isAtLiveEdge: Bool {
        secondsBehindLive < liveEdgeThresholdSeconds
    }

    public var maxLookbackSeconds: TimeInterval {
        guard let range = primarySeekableRange else { return 0 }
        return min(range.duration.seconds, maxLookbackCap)
    }

    // MARK: - Streams

    public let stateStream: AsyncStream<PlayerState>
    private let stateContinuation: AsyncStream<PlayerState>.Continuation

    /// Creates a fresh stream of audio buffers (always empty for HLS player).
    public func makeAudioBufferStream() -> AsyncStream<AVAudioPCMBuffer> {
        AsyncStream { $0.finish() }
    }

    public let eventStream: AsyncStream<AudioPlayerInternalEvent>
    private let eventContinuation: AsyncStream<AudioPlayerInternalEvent>.Continuation

    public let timePositionStream: AsyncStream<TimeInterval>
    private let timePositionContinuation: AsyncStream<TimeInterval>.Continuation

    // MARK: - Initialization

    public convenience init(url: URL) {
        self.init(
            player: AVPlayerHLSAdapter(url: url),
            analytics: StructuredPostHogAnalytics.shared,
            notificationCenter: .default
        )
    }

    init(
        player: any HLSAVPlayerProtocol,
        analytics: AnalyticsService? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        self.player = player
        self.analytics = analytics
        self.notificationCenter = notificationCenter

        var stateContinuation: AsyncStream<PlayerState>.Continuation!
        self.stateStream = AsyncStream { continuation in
            stateContinuation = continuation
        }
        self.stateContinuation = stateContinuation

        var eventContinuation: AsyncStream<AudioPlayerInternalEvent>.Continuation!
        self.eventStream = AsyncStream { continuation in
            eventContinuation = continuation
        }
        self.eventContinuation = eventContinuation

        var timePositionContinuation: AsyncStream<TimeInterval>.Continuation!
        self.timePositionStream = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            timePositionContinuation = continuation
        }
        self.timePositionContinuation = timePositionContinuation

        self.rateObservation = notificationCenter.addMainActorObserver(
            of: player as? AVPlayer,
            for: HLSRateDidChangeMessage.self
        ) { [weak self] message in
            guard let self else { return }
            Log(.info, category: .playback, "HLSPlayer did receive rate change: \(message.rate)")
            self.handleRateChange(rate: message.rate)
        }

        self.stallObservation = notificationCenter.addMainActorObserver(
            for: HLSPlaybackStalledMessage.self
        ) { [weak self] _ in
            guard let self else { return }
            Log(.error, category: .playback, "HLSPlayer playback stalled")
            self.handlePlaybackStalled()
        }

        self.failureObservation = notificationCenter.addMainActorObserver(
            for: HLSFailedToPlayToEndMessage.self
        ) { [weak self] message in
            guard let self else { return }
            Log(.error, category: .playback, "HLSPlayer failed to play to end: \(String(describing: message.error))")
            self.handleFailure(message.error)
        }
    }

    // MARK: - Playback Control

    public func play() {
        if state == .playing {
            analytics?.capture(PlaybackStartedEvent(reason: "already playing (hls)"))
            return
        }

        analytics?.capture(PlaybackStartedEvent(reason: "hlsPlayer play"))
        state = .loading
        player.play()
    }

    public func stop() {
        stopTimePositionUpdates()
        state = .idle
        player.pause()
    }

    // MARK: - Seeking

    public func seek(secondsBehindLive offset: TimeInterval) async {
        guard let range = primarySeekableRange else { return }
        let liveEdge = range.start + range.duration
        let clampedOffset = min(max(0, offset), maxLookbackSeconds)
        let targetTime = CMTime(
            seconds: liveEdge.seconds - clampedOffset,
            preferredTimescale: 600
        )
        let _ = await player.seek(to: targetTime)
        updateTimePosition()
    }

    public func seekToLive() async {
        await seek(secondsBehindLive: 0)
    }

    // MARK: - Render Tap (No-op)

    public func installRenderTap() {}
    public func removeRenderTap() {}

    // MARK: - Private

    private var primarySeekableRange: CMTimeRange? {
        player.seekableTimeRanges.first.map { $0.timeRangeValue }
    }

    private func handleRateChange(rate: Float) {
        if rate > 0 {
            if state == .loading || state == .stalled {
                if state == .stalled {
                    eventContinuation.yield(.recovery)
                }
                state = .playing
            }
        }
    }

    private func handlePlaybackStalled() {
        if state == .playing || state == .loading {
            state = .stalled
            eventContinuation.yield(.stall)
        }
    }

    private func handleFailure(_ error: (any Error)?) {
        let playbackError = PlaybackError.connectionFailed(
            error?.localizedDescription ?? "HLS playback failed"
        )
        state = .error(playbackError)
        eventContinuation.yield(.error(error ?? playbackError))
    }

    private func updateTimePosition() {
        guard let range = primarySeekableRange else {
            secondsBehindLive = 0
            return
        }
        let liveEdge = range.start + range.duration
        let current = player.currentTime()
        secondsBehindLive = max(0, liveEdge.seconds - current.seconds)
        timePositionContinuation.yield(secondsBehindLive)
    }

    private func startTimePositionUpdates() {
        guard timePositionTask == nil else { return }
        timePositionTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: timePositionUpdateInterval)
                guard let self, self.state == .playing else { break }
                self.updateTimePosition()
            }
        }
    }

    private func stopTimePositionUpdates() {
        timePositionTask?.cancel()
        timePositionTask = nil
    }
}

// MARK: - AudioPlayerProtocol + TimeShiftablePlayer

extension HLSPlayer: AudioPlayerProtocol {}
extension HLSPlayer: TimeShiftablePlayer {}
