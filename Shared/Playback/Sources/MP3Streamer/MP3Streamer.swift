//
//  MP3Streamer.swift
//  Playback
//
//  Low-latency MP3 streaming player using AVAudioEngine.
//
//  Created by Jake Bromberg on 12/07/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
import Logger
import Observation
@preconcurrency import AVFoundation
import Core
import PlaybackCore
import Analytics

/// Main audio streaming player that coordinates all components
@MainActor
@Observable
public final class MP3Streamer {
    // MARK: - Streams

    /// Stream of audio buffers for visualization - yields at render rate (~60 times/sec)
    public var audioBufferStream: AsyncStream<AVAudioPCMBuffer> {
        audioPlayer.renderTapStream
    }

    // MARK: - AudioPlayerProtocol Streams

    /// Internal state stream for AudioPlayerProtocol conformance
    internal let stateStreamInternal: AsyncStream<PlayerState>
    private let stateContinuationInternal: AsyncStream<PlayerState>.Continuation

    /// Internal event stream for AudioPlayerProtocol conformance
    internal let eventStreamInternal: AsyncStream<AudioPlayerInternalEvent>
    internal let eventContinuationInternal: AsyncStream<AudioPlayerInternalEvent>.Continuation

    public private(set) var streamingState: StreamingAudioState = .idle {
        didSet {
            if streamingState != oldValue {
                Log(.info, category: .playback, "State: \(oldValue) → \(streamingState)")
                stateContinuationInternal.yield(state)
            }
        }
    }

    /// The current player state (AudioPlayerProtocol)
    public var state: PlayerState {
        switch streamingState {
        case .idle, .paused:
            return .idle
        case .connecting, .buffering, .reconnecting:
            return .loading
        case .playing:
            return .playing
        case .stalled:
            return .stalled
        case .error(let error):
            return .error(.unknown(error.localizedDescription))
        }
    }

    public var volume: Float {
        get { audioPlayer.volume }
        set { audioPlayer.volume = newValue }
    }
    
    /// The stream URL this streamer is configured for
    private let streamURL: URL

    // MARK: - Private Properties

    @ObservationIgnored
    public let configuration: MP3StreamerConfiguration
    @ObservationIgnored
    private let httpClient: any HTTPStreamClientProtocol
    @ObservationIgnored
    private let mp3Decoder: MP3StreamDecoder
    @ObservationIgnored
    private let bufferQueue: PCMBufferQueue
    @ObservationIgnored
    internal let audioPlayer: any AudioEnginePlayerProtocol

    @ObservationIgnored
    internal var backoffTimer: ExponentialBackoff
    @ObservationIgnored
    private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored
    private var httpEventTask: Task<Void, Never>?
    @ObservationIgnored
    private var playerEventTask: Task<Void, Never>?
    @ObservationIgnored
    private let analytics: AnalyticsService?
    @ObservationIgnored
    private var playbackTimer = Timer.start()

    // Output format for decoded audio
    private static let outputFormat: AVAudioFormat = {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44100,
            channels: 2,
            interleaved: false
        ) else {
            fatalError("Failed to create audio format")
        }
        return format
    }()

    // MARK: - Initialization

    public init(
        configuration: MP3StreamerConfiguration,
        httpClient: (any HTTPStreamClientProtocol)? = nil,
        audioPlayer: (any AudioEnginePlayerProtocol)? = nil,
        backoffTimer: ExponentialBackoff = .default,
        analytics: AnalyticsService? = nil
    ) {
        self.configuration = configuration
        self.backoffTimer = backoffTimer
        self.analytics = analytics

        // Initialize state stream for AudioPlayerProtocol
        var stateContinuation: AsyncStream<PlayerState>.Continuation!
        self.stateStreamInternal = AsyncStream { continuation in
            stateContinuation = continuation
        }
        self.stateContinuationInternal = stateContinuation

        // Initialize event stream for AudioPlayerProtocol
        var eventContinuation: AsyncStream<AudioPlayerInternalEvent>.Continuation!
        self.eventStreamInternal = AsyncStream { continuation in
            eventContinuation = continuation
        }
        self.eventContinuationInternal = eventContinuation

        // Create buffer queue
        self.bufferQueue = PCMBufferQueue(
            capacity: configuration.bufferQueueSize,
            minimumBuffersBeforePlayback: configuration.minimumBuffersBeforePlayback
        )

        // Use injected dependencies or create defaults
        self.audioPlayer = audioPlayer ?? AudioEnginePlayer(format: Self.outputFormat)

        self.mp3Decoder = MP3StreamDecoder()

        self.httpClient = httpClient ?? HTTPStreamClient(
            url: configuration.url,
            configuration: configuration
        )

        self.streamURL = configuration.url

        // Start listening to event streams
        startEventListeners()
    }

    private func startEventListeners() {
        // Listen to HTTP events
        httpEventTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.httpClient.eventStream {
                guard !Task.isCancelled else { break }
                await self.handleHTTPEvent(event)
            }
        }

        // Listen to audio player events
        playerEventTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.audioPlayer.eventStream {
                guard !Task.isCancelled else { break }
                await self.handlePlayerEvent(event)
            }
        }

        // Listen to decoded buffers
        Task { [weak self] in
            guard let self else { return }
            for await buffer in self.mp3Decoder.decodedBufferStream {
                guard !Task.isCancelled else { break }
                await self.handleDecodedBuffer(buffer)
            }
        }
    }

    // MARK: - Public Methods

    /// Start streaming and playing audio
    public func play() {
        Log(.info, category: .playback, "MP3Streamer play() called (current state: \(streamingState))")
        if streamingState == .playing {
            analytics?.capture(PlaybackStartedEvent(reason: "already playing (local)"))
            return
        }

        // If paused, just resume playback
        if case .paused = streamingState {
            do {
                analytics?.capture(PlaybackStartedEvent(reason: "mp3Streamer play"))
                try audioPlayer.play()
                streamingState = .playing
            } catch {
                Log(.error, category: .playback, "Failed to resume from pause: \(error)")
                streamingState = .error(error)
                eventContinuationInternal.yield(.error(error))
            }
            return
        }

        // If in a stuck state (connecting, buffering, stalled, reconnecting, error),
        // tear down the current attempt and start fresh
        if streamingState != .idle {
            Log(.info, category: .playback, "Resetting from \(streamingState) to reconnect")
            stop()
        }

        // Connect and start streaming
        analytics?.capture(PlaybackStartedEvent(reason: "mp3Streamer play"))
        playbackTimer = Timer.start()
        streamingState = .connecting
        backoffTimer.reset()

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await httpClient.connect()
                // State will transition to buffering as data arrives
            } catch {
                Log(.error, category: .playback, "Connection failed: \(error)")
                streamingState = .error(error)
                eventContinuationInternal.yield(.error(error))
            }
        }
    }

    /// Stop playback and disconnect from stream
    public func stop() {
        Log(.info, category: .playback, "MP3Streamer stop() called")
        reconnectTask?.cancel()
        reconnectTask = nil

        httpClient.disconnect()
        audioPlayer.stop()
        bufferQueue.clear()
        mp3Decoder.reset()

        streamingState = .idle
        backoffTimer.reset()
    }

    // MARK: - Event Handlers

    private func handleHTTPEvent(_ event: HTTPStreamEvent) async {
        switch event {
        case .connected:
            Log(.info, category: .playback, "HTTP connected, starting buffering")
            streamingState = .buffering(bufferedCount: 0, requiredCount: configuration.minimumBuffersBeforePlayback)

        case .data(let data):
            mp3Decoder.decode(data: data)

        case .disconnected:
            // Only handle if we're not intentionally stopping
            guard streamingState != .idle else { return }
            Log(.warning, category: .playback, "HTTP disconnected unexpectedly")
            attemptReconnect()

        case .error(let error):
            Log(.error, category: .playback, "HTTP error: \(error)")
            streamingState = .error(error)
            attemptReconnect()
        }
    }

    private func handlePlayerEvent(_ event: AudioPlayerEvent) async {
        switch event {
        case .started:
            Log(.debug, category: .playback, "Audio engine started")

        case .paused:
            Log(.debug, category: .playback, "Audio engine paused")

        case .stopped:
            Log(.debug, category: .playback, "Audio engine stopped")

        case .error(let error):
            Log(.error, category: .playback, "Audio engine error: \(error)")
            streamingState = .error(error)
            eventContinuationInternal.yield(.error(error))

        case .needsMoreBuffers:
            scheduleBuffers()

        case .stalled:
            if case .playing = streamingState {
                Log(.warning, category: .playback, "Buffer underrun detected (stalled)")
                streamingState = .stalled
                eventContinuationInternal.yield(.stall)
            }

        case .recoveredFromStall:
            if case .stalled = streamingState {
                Log(.info, category: .playback, "Recovered from stall")
                streamingState = .playing
                eventContinuationInternal.yield(.recovery)
            }
        }
    }

    private func handleDecodedBuffer(_ buffer: AVAudioPCMBuffer) async {
        switch streamingState {
        case .playing:
            // Fast path: bypass queue entirely, schedule directly to audio player
            // This eliminates all lock acquisitions during steady-state playback
            audioPlayer.scheduleBuffer(buffer)

        case .buffering:
            // Use combined enqueue + state check (single lock acquisition)
            let result = bufferQueue.enqueue(buffer)
            if result.hasMinimumBuffers {
                Log(.info, category: .playback, "Buffer threshold reached (\(result.count)/\(configuration.minimumBuffersBeforePlayback)), starting playback")
                do {
                    try audioPlayer.play()
                    _ = playbackTimer.duration()
                    // Temporarily removed Time to first Audio event until we define a proper event for it
                    // analytics?.capture("Time to first Audio", properties: [
                    //    "timeToAudio": timeToAudio
                    // ])
                    streamingState = .playing
                    scheduleBuffers()
                } catch {
                    Log(.error, category: .playback, "Failed to start audio engine: \(error)")
                    streamingState = .error(error)
                }
            } else {
                // Still buffering - update progress using result from enqueue
                Log(.debug, category: .playback, "Buffering: \(result.count)/\(configuration.minimumBuffersBeforePlayback) buffers")
                streamingState = .buffering(
                    bufferedCount: result.count,
                    requiredCount: configuration.minimumBuffersBeforePlayback
                )
            }

        case .stalled:
            // Use combined enqueue + state check (single lock acquisition)
            let result = bufferQueue.enqueue(buffer)
            if result.hasMinimumBuffers {
                // Stall recovery - have enough buffers to resume
                Log(.info, category: .playback, "Stall recovery: buffer threshold reached")
                scheduleBuffers()
                streamingState = .playing
            }

        default:
            // idle, paused, connecting, reconnecting, error - ignore buffers
            break
        }
    }

    private func scheduleBuffers() {
        // Dequeue all available buffers at once and schedule as a batch
        // This reduces dispatch overhead by batching into a single GCD call
        let buffers = bufferQueue.dequeueAll()
        if !buffers.isEmpty {
            audioPlayer.scheduleBuffers(buffers)
        }
    }

    private func attemptReconnect() {
        guard let waitTime = backoffTimer.nextWaitTime() else {
            // Backoff exhausted - give up and transition to error state
            Log(.error, category: .playback, "Reconnect backoff exhausted after \(backoffTimer.numberOfAttempts) attempts")
            streamingState = .error(HTTPStreamError.connectionFailed)
            backoffTimer.reset()
            return
        }

        let attemptNumber = backoffTimer.numberOfAttempts
        Log(.info, category: .playback, "Reconnect attempt \(attemptNumber)/\(backoffTimer.maximumAttempts), waiting \(String(format: "%.1f", waitTime))s")

        reconnectTask = Task {
            try? await Task.sleep(for: .seconds(waitTime))

            guard !Task.isCancelled else { return }

            do {
                try await httpClient.connect()
                // Reset backoff on successful connection
                Log(.info, category: .playback, "Reconnect successful")
                backoffTimer.reset()
            } catch {
                Log(.warning, category: .playback, "Reconnect failed: \(error)")
                streamingState = .error(error)
                attemptReconnect()
            }
        }
    }
}

#if !os(watchOS)

// MARK: - AudioPlayerProtocol Conformance

extension MP3Streamer: AudioPlayerProtocol {

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

    // play() and stop() are already implemented directly in MP3Streamer

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
