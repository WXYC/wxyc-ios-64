//
//  MP3StreamerConfiguration.swift
//  Playback
//
//  Configuration for MP3 streaming buffer sizes and behavior.
//
//  Created by Jake Bromberg on 12/07/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation

/// Configuration for streaming audio playback
public struct MP3StreamerConfiguration: Sendable {
    /// The URL of the audio stream
    public let url: URL

    /// Size of the PCM buffer queue (number of buffers to maintain)
    public let bufferQueueSize: Int

    /// Minimum number of buffers before starting playback
    public let minimumBuffersBeforePlayback: Int

    /// Timeout for HTTP connection in seconds
    public let connectionTimeout: TimeInterval

    /// Hard deadline, in seconds, from a connect attempt (the initial `play()`
    /// connect or any reconnect) to reaching the `.playing` state. If playback has
    /// not started within this window the streamer escalates (emits a
    /// `startup_timeout` stream error and attempts a fresh reconnect) instead of
    /// sitting in `.connecting`/`.buffering` forever. Generous relative to the
    /// ~1.5-2s normal cold start.
    ///
    /// Precondition: this is clamped in `init` to be strictly greater than
    /// `connectionTimeout` (`max(startupTimeout, connectionTimeout + 1)`), so a pure
    /// connect failure always surfaces through its own path before the startup
    /// watchdog can fire.
    public let startupTimeout: TimeInterval

    public init(
        url: URL,
        bufferQueueSize: Int = 20,
        minimumBuffersBeforePlayback: Int = 5,
        connectionTimeout: TimeInterval = 10.0,
        startupTimeout: TimeInterval = 12.0
    ) {
        self.url = url
        self.bufferQueueSize = bufferQueueSize
        self.minimumBuffersBeforePlayback = minimumBuffersBeforePlayback
        self.connectionTimeout = connectionTimeout
        // Clamp so the startup watchdog always outlives a pure connect failure,
        // which surfaces through connectionTimeout's own path first.
        self.startupTimeout = max(startupTimeout, connectionTimeout + 1)
    }
}
