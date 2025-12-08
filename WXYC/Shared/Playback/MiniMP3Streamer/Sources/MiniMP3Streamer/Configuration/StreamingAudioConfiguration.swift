import Foundation

/// Configuration for streaming audio playback
public struct MiniMP3StreamerConfiguration: Sendable {
    /// The URL of the audio stream
    public let url: URL

    /// Whether to automatically reconnect on network failures
    public let autoReconnect: Bool

    /// Maximum number of reconnection attempts (ignored if autoReconnect is false)
    public let maxReconnectAttempts: Int

    /// Delay between reconnection attempts in seconds
    public let reconnectDelay: TimeInterval

    /// Size of the PCM buffer queue (number of buffers to maintain)
    public let bufferQueueSize: Int

    /// Minimum number of buffers before starting playback
    public let minimumBuffersBeforePlayback: Int

    /// Timeout for HTTP connection in seconds
    public let connectionTimeout: TimeInterval

    public init(
        url: URL,
        autoReconnect: Bool = true,
        maxReconnectAttempts: Int = 3,
        reconnectDelay: TimeInterval = 2.0,
        bufferQueueSize: Int = 20,
        minimumBuffersBeforePlayback: Int = 5,
        connectionTimeout: TimeInterval = 10.0
    ) {
        self.url = url
        self.autoReconnect = autoReconnect
        self.maxReconnectAttempts = maxReconnectAttempts
        self.reconnectDelay = reconnectDelay
        self.bufferQueueSize = bufferQueueSize
        self.minimumBuffersBeforePlayback = minimumBuffersBeforePlayback
        self.connectionTimeout = connectionTimeout
    }
}
