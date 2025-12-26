import Foundation
import Observation
@preconcurrency import AVFoundation
import Core

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

    public private(set) var state: StreamingAudioState = .idle {
        didSet {
            if state != oldValue {
                delegate?.audioStreamer(didChangeState: state)
            }
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

        // Create delegate adapters
        let httpAdapter = HTTPStreamClientDelegateAdapter()
        let decoderAdapter = MP3DecoderDelegateAdapter()
        let playerAdapter = AudioPlayerDelegateAdapter()

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
    public func play() async throws {
        guard state == .idle || state == .paused else { return }

        // If paused, just resume playback
        if case .paused = state {
            try audioPlayer.play()
            state = .playing
            return
        }

        // Otherwise, connect and start streaming
        state = .connecting
        backoffTimer.reset()

        do {
            try await httpClient.connect()
            // State will transition to buffering as data arrives
        } catch {
            state = .error(error)
            delegate?.audioStreamer(didEncounterError: error)
            throw error
        }
    }

    /// Pause playback and reset stream for live playback.
    /// Unlike stop(), pause() preserves backoff state for consistent retry behavior.
    /// For live streaming, we disconnect completely so resume connects to live audio,
    /// not stale buffered audio.
    public func pause() {
        guard case .playing = state else { return }

        reconnectTask?.cancel()
        reconnectTask = nil

        httpClient.disconnect()
        audioPlayer.stop()
        bufferQueue.clear()
        mp3Decoder.reset()

        state = .paused
        // Note: Don't reset backoffTimer - preserve retry state for session continuity
    }

    /// Stop playback and disconnect
    public func stop() {
        reconnectTask?.cancel()
        reconnectTask = nil

        httpClient.disconnect()
        audioPlayer.stop()
        bufferQueue.clear()
        mp3Decoder.reset()

        state = .idle
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
        if case .buffering = state, bufferQueue.hasMinimumBuffers {
            do {
                try audioPlayer.play()
                state = .playing
                scheduleBuffers()
            } catch {
                state = .error(error)
                delegate?.audioStreamer(didEncounterError: error)
            }
        }

        // If already playing, schedule this buffer
        if case .playing = state {
            scheduleBuffers()
        }

        // Update buffering state
        if case .buffering = state {
            state = .buffering(
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
        state = .buffering(bufferedCount: 0, requiredCount: configuration.minimumBuffersBeforePlayback)
    }

    fileprivate func handleHTTPDisconnected() {
        // Only handle if we're not intentionally stopping
        guard state != .idle else { return }

        attemptReconnect()
    }

    fileprivate func handleError(_ error: Error) {
        state = .error(error)
        delegate?.audioStreamer(didEncounterError: error)

        attemptReconnect()
    }

    fileprivate func attemptReconnect() {
        let waitTime = backoffTimer.nextWaitTime()

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
        if case .playing = state {
            state = .stalled
            delegate?.audioStreamerDidStall(self)
        }
    }

    internal func handleRecovery() {
        if case .stalled = state {
            state = .playing
            delegate?.audioStreamerDidRecover(self)
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
