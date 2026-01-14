//
//  PlaybackAnalytics.swift
//  Playback
//
//  Unified analytics protocol for playback events.
//  Replaces the scattered AudioAnalyticsProtocol and PlaybackMetricsReporter.
//
//  Created by Jake Bromberg on 12/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation

// MARK: - Start/Stop Reasons

/// Reason why playback was started.
public enum PlaybackStartReason: Sendable, Equatable {
    /// User explicitly initiated playback (tap, button press)
    case userInitiated
    /// Automatic reconnection after network recovery
    case autoReconnect
    /// Resuming after system interruption ended
    case interruptionEnded
    /// Remote command (CarPlay, headphones, Control Center)
    case remoteCommand

    /// Creates a PlaybackStartReason from a legacy string reason.
    public init(fromLegacyReason reason: String) {
        switch reason.lowercased() {
        case let r where r.contains("remote"):
            self = .remoteCommand
        case let r where r.contains("resume") || r.contains("interruption"):
            self = .interruptionEnded
        case let r where r.contains("reconnect") || r.contains("backoff"):
            self = .autoReconnect
        default:
            self = .userInitiated
        }
    }
}

/// Reason why playback was stopped.
public enum PlaybackStopReason: Sendable, Equatable {
    /// User explicitly stopped playback
    case userInitiated
    /// Playback stopped due to an error
    case error(PlaybackError)
    /// System interruption began (phone call, Siri, etc.)
    case interruptionBegan
    /// Playback stalled due to buffer underrun
    case stall
}

// MARK: - Interruption Type

/// Type of audio session interruption.
public enum InterruptionType: Sendable, Equatable {
    /// Interruption began (e.g., phone call started)
    case began
    /// Interruption ended, playback can resume
    case ended
    /// Audio route was disconnected (e.g., Bluetooth headphones disconnected)
    case routeDisconnected
}

// MARK: - Event Types

/// Marker protocol for all playback analytics events.
public protocol PlaybackAnalyticsEvent: Sendable, Equatable {}

/// Event capturing that playback started.
public struct PlaybackStartedEvent: PlaybackAnalyticsEvent {
    /// Why playback was initiated (freeform string for PostHog compatibility)
    public let reason: String

    public init(reason: String) {
        self.reason = reason
    }
}

/// Event capturing that playback stopped.
public struct PlaybackStoppedEvent: PlaybackAnalyticsEvent {
    /// Why playback was stopped (optional freeform string for PostHog compatibility)
    public let reason: String?
    /// How long playback lasted in seconds
    public let duration: TimeInterval

    public init(reason: String? = nil, duration: TimeInterval) {
        self.reason = reason
        self.duration = duration
    }
}

/// Reason why playback stalled.
public enum StallReason: String, Sendable, Equatable {
    case bufferUnderrun = "buffer_underrun"
    case networkError = "network_error"
    case unknown = "unknown"
}

/// Method used to recover from a stall.
public enum RecoveryMethod: String, Sendable, Equatable {
    case automaticReconnect = "automatic_reconnect"
    case retryWithBackoff = "retry_with_backoff"
    case bufferRefill = "buffer_refill"
    case streamRestart = "stream_restart"
    case userInitiated = "user_initiated"
}

/// Event capturing recovery from a stall.
public struct StallRecoveryEvent: PlaybackAnalyticsEvent {
    /// The type of player that recovered
    public let playerType: PlayerControllerType
    /// Whether recovery was successful
    public let successful: Bool
    /// Number of reconnection attempts before recovery
    public let attempts: Int
    /// How long the stall lasted in seconds
    public let stallDuration: TimeInterval
    /// Why the stall occurred
    public let reason: StallReason
    /// How recovery was achieved
    public let recoveryMethod: RecoveryMethod

    public init(
        playerType: PlayerControllerType,
        successful: Bool = true,
        attempts: Int,
        stallDuration: TimeInterval,
        reason: StallReason = .bufferUnderrun,
        recoveryMethod: RecoveryMethod = .bufferRefill
    ) {
        self.playerType = playerType
        self.successful = successful
        self.attempts = attempts
        self.stallDuration = stallDuration
        self.reason = reason
        self.recoveryMethod = recoveryMethod
    }
}

/// Event capturing an audio session interruption.
public struct InterruptionEvent: PlaybackAnalyticsEvent {
    /// The type of interruption
    public let type: InterruptionType

    public init(type: InterruptionType) {
        self.type = type
    }
}

/// Event capturing an error during playback.
public struct ErrorEvent: PlaybackAnalyticsEvent {
    /// Description of the error
    public let error: String
    /// Context where the error occurred
    public let context: String

    public init(error: Error, context: String) {
        self.error = error.localizedDescription
        self.context = context
    }

    public init(error: String, context: String) {
        self.error = error
        self.context = context
    }
}

/// Event capturing CPU usage during playback.
public struct CPUUsageEvent: PlaybackAnalyticsEvent {
    /// The type of player being monitored
    public let playerType: PlayerControllerType
    /// CPU usage as a percentage (0.0 - 100.0)
    public let cpuUsage: Double

    public init(playerType: PlayerControllerType, cpuUsage: Double) {
        self.playerType = playerType
        self.cpuUsage = cpuUsage
    }
}

// MARK: - CPU Session Analytics

/// Reason why a CPU monitoring session ended.
public enum CPUSessionEndReason: String, Sendable, Equatable {
    /// User explicitly stopped playback
    case userStopped = "user_stopped"
    /// App transitioned to background
    case backgrounded = "backgrounded"
    /// App returned to foreground
    case foregrounded = "foregrounded"
    /// Playback was interrupted (phone call, Siri, etc.)
    case interrupted = "interrupted"
    /// Playback stalled due to buffer underrun
    case stalled = "stalled"
    /// Audio route disconnected (headphones unplugged)
    case routeDisconnected = "route_disconnected"
    /// Error occurred during playback
    case error = "error"
}

/// Whether the session was in foreground or background.
public enum PlaybackContext: String, Sendable, Equatable {
    case foreground
    case background
}

/// Aggregated CPU usage statistics for a playback session.
///
/// Reports average and maximum CPU usage over a playback session,
/// distinguishing between foreground and background playback.
public struct CPUSessionEvent: PlaybackAnalyticsEvent {
    /// The type of player being monitored
    public let playerType: PlayerControllerType
    /// Whether this was foreground or background playback
    public let context: PlaybackContext
    /// Why this session ended
    public let endReason: CPUSessionEndReason
    /// Average CPU usage over the session (0.0 - 100.0+)
    public let averageCPU: Double
    /// Maximum CPU usage observed (0.0 - 100.0+)
    public let maxCPU: Double
    /// Number of samples collected
    public let sampleCount: Int
    /// Session duration in seconds
    public let durationSeconds: TimeInterval

    public init(
        playerType: PlayerControllerType,
        context: PlaybackContext,
        endReason: CPUSessionEndReason,
        averageCPU: Double,
        maxCPU: Double,
        sampleCount: Int,
        durationSeconds: TimeInterval
    ) {
        self.playerType = playerType
        self.context = context
        self.endReason = endReason
        self.averageCPU = averageCPU
        self.maxCPU = maxCPU
        self.sampleCount = sampleCount
        self.durationSeconds = durationSeconds
    }
}

// MARK: - PlaybackAnalytics Protocol

/// Protocol for capturing playback analytics events.
///
/// This is the single source of truth for playback analytics,
/// consolidating the previous AudioAnalyticsProtocol and PlaybackMetricsReporter.
@MainActor
public protocol PlaybackAnalytics: AnyObject {
    /// Capture that playback started.
    func capture(_ event: PlaybackStartedEvent)

    /// Capture that playback stopped.
    func capture(_ event: PlaybackStoppedEvent)

    /// Capture recovery from a stall.
    func capture(_ event: StallRecoveryEvent)

    /// Capture an audio session interruption.
    func capture(_ event: InterruptionEvent)

    /// Capture an error that occurred during playback.
    func capture(_ event: ErrorEvent)

    /// Capture CPU usage during playback.
    func capture(_ event: CPUUsageEvent)

    /// Capture aggregated CPU session statistics.
    func capture(_ event: CPUSessionEvent)
}
