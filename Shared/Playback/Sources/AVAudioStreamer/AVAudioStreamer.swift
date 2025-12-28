import Foundation
import Observation
@preconcurrency import AVFoundation
import Core
import PlaybackCore

/// Main audio streaming player that coordinates all components
@MainActor
@Observable
public final class AVAudioStreamer {
    // MARK: - Public Properties

    public weak var delegate: (any AVAudioStreamerDelegate)?
    
    // MARK: - Streams
    
    public var audioBufferStream: AsyncStream<AVAudioPCMBuffer> {
        audioBufferStreamContinuation.0
    }
    
    // Use .bufferingNewest(1) to avoid blocking decoding thread
    private let audioBufferStreamContinuation: (AsyncStream<AVAudioPCMBuffer>, AsyncStream<AVAudioPCMBuffer>.Continuation) = {
        var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation!
        let stream = AsyncStream<AVAudioPCMBuffer>(bufferingPolicy: .bufferingNewest(1)) { c in
            continuation = c
        }
        return (stream, continuation)
    }()

    // MARK: - AudioPlayerProtocol Streams

    /// Internal state stream for AudioPlayerProtocol conformance
    internal let stateStreamInternal: AsyncStream<PlaybackState>
    private let stateContinuationInternal: AsyncStream<PlaybackState>.Continuation

    /// Internal event stream for AudioPlayerProtocol conformance
    internal let eventStreamInternal: AsyncStream<AudioPlayerInternalEvent>
    internal let eventContinuationInternal: AsyncStream<AudioPlayerInternalEvent>.Continuation

    public private(set) var streamingState: StreamingAudioState = .idle {
        didSet {
            if streamingState != oldValue {
                delegate?.audioStreamer(didChangeState: streamingState)
                // Yield to AudioPlayerProtocol stateStream
                stateContinuationInternal.yield(state)
            }
        }
    }

    /// The current playback state (PlaybackController protocol)
    public var state: PlaybackState {
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
    public let configuration: AVAudioStreamerConfiguration
    @ObservationIgnored
    private let httpClient: HTTPStreamClient
    @ObservationIgnored
    private let mp3Decoder: MP3StreamDecoder
    @ObservationIgnored
    private let bufferQueue: PCMBufferQueue
    @ObservationIgnored
    private let httpAdapter: HTTPStreamClientDelegateAdapter
    @ObservationIgnored
    private let decoderAdapter: MP3DecoderDelegateAdapter
    @ObservationIgnored
    private let playerAdapter: AudioPlayerDelegateAdapter
    @ObservationIgnored
    private let audioPlayer: AudioEnginePlayer

    @ObservationIgnored
    internal var backoffTimer: ExponentialBackoff
    @ObservationIgnored
    private var reconnectTask: Task<Void, Never>?

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
        configuration: AVAudioStreamerConfiguration,
        backoffTimer: ExponentialBackoff = .default
    ) {
        self.configuration = configuration
        self.backoffTimer = backoffTimer
        
        // Initialize state stream for AudioPlayerProtocol
        var stateContinuation: AsyncStream<PlaybackState>.Continuation!
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

        // Create delegate adapters (stored as properties to prevent deallocation)
        self.httpAdapter = HTTPStreamClientDelegateAdapter()
        self.decoderAdapter = MP3DecoderDelegateAdapter()
        self.playerAdapter = AudioPlayerDelegateAdapter()

        // Create buffer queue
        self.bufferQueue = PCMBufferQueue(
            capacity: configuration.bufferQueueSize,
            minimumBuffersBeforePlayback: configuration.minimumBuffersBeforePlayback,
            delegate: nil
        )

        // Create components with their adapters
        self.audioPlayer = AudioEnginePlayer(
            format: Self.outputFormat,
            delegate: playerAdapter
        )

        self.mp3Decoder = MP3StreamDecoder(
            delegate: decoderAdapter
        )

        self.httpClient = HTTPStreamClient(
            url: configuration.url,
            configuration: configuration,
            delegate: httpAdapter
        )
        
        self.streamURL = configuration.url

        // Connect adapters back to self
        httpAdapter.streamer = self
        decoderAdapter.streamer = self
        playerAdapter.streamer = self
    }

    // MARK: - Public Methods

    /// Start streaming and playing audio
    public func play() {
        guard streamingState == .idle || streamingState == .paused else { return }

        // If paused, just resume playback
        if case .paused = streamingState {
            do {
                try audioPlayer.play()
                streamingState = .playing
            } catch {
                streamingState = .error(error)
                eventContinuationInternal.yield(.error(error))
            }
            return
        }

        // Otherwise, connect and start streaming
        streamingState = .connecting
        backoffTimer.reset()

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await httpClient.connect()
                // State will transition to buffering as data arrives
            } catch {
                streamingState = .error(error)
                eventContinuationInternal.yield(.error(error))
            }
        }
    }

    /// Stop playback and disconnect from stream
    public func stop() {
        reconnectTask?.cancel()
        reconnectTask = nil

        httpClient.disconnect()
        audioPlayer.stop()
        bufferQueue.clear()
        mp3Decoder.reset()

        streamingState = .idle
        backoffTimer.reset()
    }

    // MARK: - Private Methods

    fileprivate func handleHTTPData(_ data: Data) {
        mp3Decoder.decode(data: data)
    }

    fileprivate func handleDecodedBuffer(_ buffer: AVAudioPCMBuffer) {
        // Add to queue
        bufferQueue.enqueue(buffer)

        // Notify delegate and stream
        delegate?.audioStreamer(didOutput: buffer, at: nil)
        audioBufferStreamContinuation.1.yield(buffer)

        // Check if we should start playing
        if case .buffering = streamingState, bufferQueue.hasMinimumBuffers {
            do {
                try audioPlayer.play()
                streamingState = .playing
                scheduleBuffers()
            } catch {
                streamingState = .error(error)
            }
        }

        // If already playing, schedule this buffer
        if case .playing = streamingState {
            scheduleBuffers()
        }

        // Update buffering state
        if case .buffering = streamingState {
            streamingState = .buffering(
                bufferedCount: bufferQueue.count,
                requiredCount: configuration.minimumBuffersBeforePlayback
            )
        }
    }

    fileprivate func scheduleBuffers() {
        // Schedule available buffers
        while let buffer = bufferQueue.dequeue() {
            audioPlayer.scheduleBuffer(buffer)
        }
    }

    fileprivate func handleHTTPConnected() {
        streamingState = .buffering(bufferedCount: 0, requiredCount: configuration.minimumBuffersBeforePlayback)
    }

    fileprivate func handleHTTPDisconnected() {
        // Only handle if we're not intentionally stopping
        guard streamingState != .idle else { return }

        attemptReconnect()
    }

    fileprivate func handleError(_ error: Error) {
        streamingState = .error(error)
        attemptReconnect()
    }

    fileprivate func attemptReconnect() {
        guard let waitTime = backoffTimer.nextWaitTime() else {
            // Backoff exhausted - give up and transition to error state
            streamingState = .error(HTTPStreamError.connectionFailed)
            backoffTimer.reset()
            return
        }

        reconnectTask = Task {
            try? await Task.sleep(for: .seconds(waitTime))

            guard !Task.isCancelled else { return }

            do {
                try await httpClient.connect()
                // Reset backoff on successful connection
                backoffTimer.reset()
            } catch {
                handleError(error)
            }
        }
    }

    internal func handleStall() {
        if case .playing = streamingState {
            streamingState = .stalled
            delegate?.audioStreamerDidStall(self)
            eventContinuationInternal.yield(.stall)
        }
    }

    internal func handleRecovery() {
        if case .stalled = streamingState {
            streamingState = .playing
            delegate?.audioStreamerDidRecover(self)
            eventContinuationInternal.yield(.recovery)
        }
    }
}

// MARK: - Delegate Adapters

private final class HTTPStreamClientDelegateAdapter: HTTPStreamClientDelegate, @unchecked Sendable {
    weak var streamer: AVAudioStreamer?

    func httpStreamClient(_ client: HTTPStreamClient, didReceiveData data: Data) {
        Task { @MainActor in
            streamer?.handleHTTPData(data)
        }
    }

    func httpStreamClientDidConnect(_ client: HTTPStreamClient) {
        Task { @MainActor in
            streamer?.handleHTTPConnected()
        }
    }

    func httpStreamClientDidDisconnect(_ client: HTTPStreamClient) {
        Task { @MainActor in
            streamer?.handleHTTPDisconnected()
        }
    }

    func httpStreamClient(_ client: HTTPStreamClient, didEncounterError error: Error) {
        Task { @MainActor in
            streamer?.handleError(error)
        }
    }
}

private final class MP3DecoderDelegateAdapter: MP3DecoderDelegate, @unchecked Sendable {
    weak var streamer: AVAudioStreamer?

    func mp3Decoder(_ decoder: MP3StreamDecoder, didDecode buffer: AVAudioPCMBuffer) {
        Task { @MainActor in
            streamer?.handleDecodedBuffer(buffer)
        }
    }

    func mp3Decoder(_ decoder: MP3StreamDecoder, didEncounterError error: Error) {
        Task { @MainActor in
            streamer?.handleError(error)
        }
    }
}

private final class AudioPlayerDelegateAdapter: AudioPlayerDelegate, @unchecked Sendable {
    weak var streamer: AVAudioStreamer?

    func audioPlayerDidStartPlaying(_ player: AudioEnginePlayer) {
        // Handled by streamer
    }

    func audioPlayerDidPause(_ player: AudioEnginePlayer) {
        // Handled by streamer
    }

    func audioPlayerDidStop(_ player: AudioEnginePlayer) {
        // Handled by streamer
    }

    func audioPlayer(_ player: AudioEnginePlayer, didEncounterError error: Error) {
        Task { @MainActor in
            streamer?.handleError(error)
        }
    }

    func audioPlayerNeedsMoreBuffers(_ player: AudioEnginePlayer) {
        Task { @MainActor in
            streamer?.scheduleBuffers()
        }
    }

    func audioPlayerDidStall(_ player: AudioEnginePlayer) {
        Task { @MainActor in
            streamer?.handleStall()
        }
    }

    func audioPlayerDidRecoverFromStall(_ player: AudioEnginePlayer) {
        Task { @MainActor in
            streamer?.handleRecovery()
        }
    }
}
