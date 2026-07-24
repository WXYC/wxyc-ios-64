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

    /// Creates a fresh stream of audio buffers for visualization.
    /// Yields at render rate (~60 times/sec). Each call returns a new stream.
    public func makeAudioBufferStream() -> AsyncStream<AVAudioPCMBuffer> {
        audioPlayer.makeRenderTapStream()
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

    /// Output gain applied to the stream, in decibels. `0` is unity (no boost).
    /// Forwarded to the underlying `AudioEnginePlayer`'s gain stage.
    public var gainDecibels: Float {
        get { audioPlayer.gainDecibels }
        set { audioPlayer.gainDecibels = newValue }
    }

    /// The stream URL this streamer is configured for
    private let streamURL: URL

    // MARK: - Private Properties

    @ObservationIgnored
    public let configuration: MP3StreamerConfiguration
    @ObservationIgnored
    private let httpClient: any HTTPStreamClientProtocol
    @ObservationIgnored
    private var mp3Decoder: MP3StreamDecoder
    @ObservationIgnored
    private let bufferQueue: PCMBufferQueue
    @ObservationIgnored
    internal let audioPlayer: any AudioEnginePlayerProtocol

    @ObservationIgnored
    internal var backoffTimer: ExponentialBackoff
    @ObservationIgnored
    private var reconnectTask: Task<Void, Never>?
    /// The deferred connect Task enqueued by `play()`. Stored so a racing `stop()`
    /// (or a superseding `play()`) can cancel it before it connects — otherwise a
    /// stopped streamer gets resurrected into `.buffering` with a live watchdog.
    /// See issue #488.
    @ObservationIgnored
    private var startupConnectTask: Task<Void, Never>?
    @ObservationIgnored
    private var startupWatchdogTask: Task<Void, Never>?
    @ObservationIgnored
    private var httpEventTask: Task<Void, Never>?
    @ObservationIgnored
    private var playerEventTask: Task<Void, Never>?
    @ObservationIgnored
    private var decoderConsumerTask: Task<Void, Never>?
    @ObservationIgnored
    private let analytics: AnalyticsService?
    @ObservationIgnored
    private var playbackTimer = Timer.start()
    /// Whether the `.firstAudio` success event has already been emitted for the
    /// current playback session. Set once when buffering first crosses into
    /// `.playing`; it deliberately survives reconnect recovery (so a reconnect
    /// does not double-count a start) and is reset only on a fresh `play()` or
    /// `stop()`. See issue #513.
    @ObservationIgnored
    private var hasEmittedFirstAudio = false

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

        startDecoderConsumer()
    }

    private func startDecoderConsumer() {
        decoderConsumerTask = Task { [weak self] in
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
        // perform a non-blocking teardown before reconnecting. The teardown is moved
        // into the async Task to avoid blocking the main thread — previously stop()
        // was called synchronously here, which could deadlock when the decoder queue
        // was busy with a long conversion loop (0x8BADF00D watchdog kill).
        let needsTeardown = streamingState != .idle
        if needsTeardown {
            Log(.info, category: .playback, "Resetting from \(streamingState) to reconnect")
            // Cancel any pending reconnect task eagerly to prevent it from racing
            // with the new connection attempt. This is safe and non-blocking.
            reconnectTask?.cancel()
            reconnectTask = nil
        }

        // Connect and start streaming
        analytics?.capture(PlaybackStartedEvent(reason: "mp3Streamer play"))
        playbackTimer = Timer.start()
        // Fresh session: the next buffering→playing crossing should count as a
        // new successful start.
        hasEmittedFirstAudio = false
        streamingState = .connecting

        // Supersede any deferred connect Task still pending from a prior play(),
        // then store this one so a racing stop() can cancel it (issue #488).
        startupConnectTask?.cancel()
        startupConnectTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }
            if needsTeardown {
                // Tear down stream I/O without cancelling this Task (resetStreamIO
                // does not touch startupConnectTask — a self-cancel here would defeat
                // the purpose). Then restore .connecting and reset the backoff ramp:
                // resetStreamIO() does not reset the backoff, and this branch no
                // longer routes through stop() which used to, so without this an
                // interrupted mid-reconnect ramp would carry over.
                resetStreamIO()
                streamingState = .connecting
                backoffTimer.reset()
            }
            // A stop() (or superseding play()) that landed while this Task was
            // pending cancels it; connect() is not cancellation-aware, so re-check
            // here before doing any I/O. Guarding on .connecting also aborts a Task
            // whose state was torn out from under it. See issue #488, Sentry IOS-31.
            guard streamingState == .connecting, !Task.isCancelled else { return }
            // Arm the startup watchdog once the (possibly torn-down) state has
            // settled back to .connecting, immediately before connecting.
            armStartupWatchdog()
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
        cancelStartupWatchdog()
        // Cancel a deferred connect Task still pending from play() so a stop() that
        // races it can't leave the streamer resurrected (issue #488).
        startupConnectTask?.cancel()
        startupConnectTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil

        resetStreamIO()

        streamingState = .idle
        backoffTimer.reset()
        // The session is over; the next play() starts a fresh first-audio window.
        hasEmittedFirstAudio = false
    }

    /// Tears down the active stream I/O — disconnects HTTP, stops the audio engine,
    /// clears the buffer queue, and replaces the decoder with a fresh instance —
    /// without touching `startupConnectTask`, `streamingState`, or the backoff timer.
    /// Shared by `stop()` and `play()`'s stuck-state teardown so the latter does not
    /// self-cancel its own deferred connect Task. See issue #488.
    private func resetStreamIO() {
        httpClient.disconnect()
        audioPlayer.stop()
        bufferQueue.clear()

        // Cancel the old decoder consumer and replace the decoder with a fresh instance.
        // This eliminates stale decoded buffers that may remain in the old decoder's
        // AsyncStream buffer (up to 32 frames with .bufferingOldest policy).
        // The old decoder's deinit calls bufferContinuation.finish(), cleanly terminating
        // the old consumer's for-await loop.
        decoderConsumerTask?.cancel()
        mp3Decoder.reset()
        mp3Decoder = MP3StreamDecoder()
        startDecoderConsumer()
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
            // Only reconnect from states where an unexpected disconnect is meaningful.
            // States like .connecting, .reconnecting, .idle, .paused, and .error must
            // not trigger reconnect — this prevents spurious reconnects from stale
            // .disconnected events that arrive after stop()/play() recovery cycles.
            switch streamingState {
            case .playing, .buffering, .stalled:
                Log(.warning, category: .playback, "HTTP disconnected unexpectedly")
                attemptReconnect()
            default:
                break
            }

        case .error(let error):
            Log(.error, category: .playback, "HTTP error: \(error)")
            streamingState = .error(error)
            // Deliberately NOT yielded to the internal event stream (#486): this is
            // the transient pre-reconnect drop that usually recovers on the next
            // connect. Emitting a StreamErrorEvent here would count a routine blip
            // as a failure. The terminal outcome — recovery (.firstAudio/.recovery)
            // or backoff exhaustion (yielded in attemptReconnect) — is what counts.
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
                    // Playback started — disarm the startup watchdog.
                    cancelStartupWatchdog()
                    streamingState = .playing
                    // Emit the "first audio" success signal exactly once per
                    // session. This is the denominator for the playback-start
                    // success rate (issue #513). It is forwarded through the
                    // internal event stream — not captured directly here — so
                    // MP3Streamer stays free of analytics and success/failure are
                    // counted at the same AudioPlayerController layer. Guarding on
                    // `hasEmittedFirstAudio` keeps reconnect recovery from
                    // double-counting a start (that is `stall_recovery`'s job).
                    if !hasEmittedFirstAudio {
                        hasEmittedFirstAudio = true
                        eventContinuationInternal.yield(.firstAudio(timeToAudio: playbackTimer.duration()))
                    }
                    scheduleBuffers()
                } catch {
                    Log(.error, category: .playback, "Failed to start audio engine: \(error)")
                    streamingState = .error(error)
                    // Terminal, non-recursive failure: the buffer threshold was
                    // crossed but the engine refused to start, so playback silently
                    // never begins. Surface it once through the internal event stream
                    // so the controller captures a StreamErrorEvent — this is the
                    // failure numerator against #513's first-audio denominator (#486).
                    eventContinuationInternal.yield(.error(error))
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

    // MARK: - Startup Watchdog

    /// Arms a one-shot deadline spanning a fresh connect attempt through reaching
    /// `.playing`. If the deadline elapses while still `.connecting`/`.buffering`
    /// — i.e. the stream connected but starved before playback began — the
    /// streamer escalates instead of hanging in a perpetual loading state.
    /// See Sentry IOS-31 ("Playback not starting").
    private func armStartupWatchdog() {
        startupWatchdogTask?.cancel()
        let timeout = configuration.startupTimeout
        startupWatchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard let self, !Task.isCancelled else { return }
            self.handleStartupTimeout()
        }
    }

    private func cancelStartupWatchdog() {
        startupWatchdogTask?.cancel()
        startupWatchdogTask = nil
    }

    /// Fired when playback failed to begin within `startupTimeout`. Escalates only
    /// from a pre-playing state; emits a `startup_timeout` stream error (so the
    /// failure is visible in analytics/Sentry, where it was previously silent) and
    /// attempts a fresh reconnect.
    private func handleStartupTimeout() {
        startupWatchdogTask = nil
        switch streamingState {
        case .connecting, .buffering:
            let error = StreamStartupError.timedOut(seconds: configuration.startupTimeout)
            Log(.error, category: .playback, "Startup watchdog fired: playback did not begin within \(configuration.startupTimeout)s (state: \(streamingState)); escalating to reconnect")
            streamingState = .error(error)
            // Surface the failure through the internal event stream so the
            // controller captures a StreamErrorEvent (classified as startupTimeout).
            eventContinuationInternal.yield(.error(error))
            // Cancel any reconnect already in flight (e.g. one scheduled by a
            // mid-startup HTTP disconnect) before starting a fresh one. Otherwise
            // attemptReconnect() would overwrite the single reconnectTask handle,
            // leaking the pending task to run to completion alongside the new one.
            reconnectTask?.cancel()
            reconnectTask = nil
            attemptReconnect()
        default:
            // Already playing, stopped, or errored via another path — nothing to do.
            break
        }
    }

    private func attemptReconnect() {
        guard let waitTime = backoffTimer.nextWaitTime() else {
            // Backoff exhausted - give up and transition to error state
            Log(.error, category: .playback, "Reconnect backoff exhausted after \(backoffTimer.numberOfAttempts) attempts")
            let error = HTTPStreamError.connectionFailed
            streamingState = .error(error)
            // Terminal, non-recursive failure: MP3Streamer has given up its HTTP
            // reconnects for this episode. Surface it exactly once through the
            // internal event stream so the controller captures a StreamErrorEvent
            // (#486). The exhaustion boundary is reached at most once per episode
            // (the ramp does not re-enter here), so no per-attempt over-counting.
            eventContinuationInternal.yield(.error(error))
            backoffTimer.reset()
            return
        }

        let attemptNumber = backoffTimer.numberOfAttempts
        Log(.info, category: .playback, "Reconnect attempt \(attemptNumber)/\(backoffTimer.maximumAttempts), waiting \(String(format: "%.1f", waitTime))s")

        reconnectTask = Task {
            try? await Task.sleep(for: .seconds(waitTime))

            guard !Task.isCancelled else { return }

            // Re-arm the startup watchdog so its deadline now spans reconnect connects
            // too, not just the initial connect in play(). A reconnect that connects
            // (HTTP 200 → .buffering) then starves before .playing would otherwise
            // park with no live deadline and hang silently (Sentry IOS-34). This is
            // idempotent — armStartupWatchdog() self-cancels any prior watchdog — and
            // the .playing transition disarms it on a successful reconnect.
            armStartupWatchdog()

            do {
                try await httpClient.connect()
                // Reset backoff on successful connection
                Log(.info, category: .playback, "Reconnect successful")
                backoffTimer.reset()
            } catch {
                Log(.warning, category: .playback, "Reconnect failed: \(error)")
                streamingState = .error(error)
                // Deliberately NOT yielded to the internal event stream (#486): this
                // catch recurses once per failed reconnect attempt, so yielding here
                // would emit one StreamErrorEvent PER attempt and over-count failures
                // against #513's first-audio denominator. The single terminal signal
                // is emitted once at backoff exhaustion (the guard above).
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

// MARK: - GainBoostablePlayer Conformance

/// MP3Streamer supports a decibel output boost via its `AudioEnginePlayer` gain
/// stage. `gainDecibels` is declared on the main type; this marks the capability
/// for `as? GainBoostablePlayer` discovery at the controller layer.
extension MP3Streamer: GainBoostablePlayer {}

#endif // !os(watchOS)
