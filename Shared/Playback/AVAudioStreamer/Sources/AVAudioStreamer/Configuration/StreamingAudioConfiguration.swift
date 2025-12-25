import Foundation

/// Configuration for streaming audio playback
public struct AVAudioStreamerConfiguration: Sendable {
    /// The URL of the audio stream
    public let url: URL

    /// Size of the PCM buffer queue (number of buffers to maintain)
    public let bufferQueueSize: Int

    /// Minimum number of buffers before starting playback
    public let minimumBuffersBeforePlayback: Int

    /// Timeout for HTTP connection in seconds
    public let connectionTimeout: TimeInterval

    public init(
        url: URL,
        bufferQueueSize: Int = 20,
        minimumBuffersBeforePlayback: Int = 5,
        connectionTimeout: TimeInterval = 10.0
    ) {
        self.url = url
        self.bufferQueueSize = bufferQueueSize
        self.minimumBuffersBeforePlayback = minimumBuffersBeforePlayback
        self.connectionTimeout = connectionTimeout
    }
}
