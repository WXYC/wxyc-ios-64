#if !os(watchOS)

@preconcurrency import AVFoundation

/// Events emitted by an audio engine player
public enum AudioPlayerEvent: Sendable {
    /// Playback started
    case started
    /// Playback paused
    case paused
    /// Playback stopped
    case stopped
    /// An error occurred
    case error(Error)
    /// Player needs more buffers to continue
    case needsMoreBuffers
    /// Playback stalled due to buffer underrun
    case stalled
    /// Playback recovered from a stall
    case recoveredFromStall
}

/// Protocol for audio engine players, enabling dependency injection for testing
public protocol AudioEnginePlayerProtocol: AnyObject, Sendable {
    /// The current volume level (0.0 to 1.0)
    var volume: Float { get set }

    /// Whether the player is currently playing
    var isPlaying: Bool { get }

    /// Stream of player events
    var eventStream: AsyncStream<AudioPlayerEvent> { get }

    /// Stream of audio buffers from the render tap for visualization
    var renderTapStream: AsyncStream<AVAudioPCMBuffer> { get }

    /// Start playback
    func play() throws

    /// Pause playback
    func pause()

    /// Stop playback and reset
    func stop()

    /// Schedule a buffer for playback
    func scheduleBuffer(_ buffer: AVAudioPCMBuffer)
}

#endif
