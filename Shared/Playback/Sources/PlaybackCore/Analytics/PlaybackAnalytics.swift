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

// MARK: - Interruption Type

/// Type of audio session interruption.
public enum InterruptionType: String, Sendable, Equatable {
    case began
    case ended
    case routeDisconnected = "route_disconnected"
}

// MARK: - Event Types

/// Marker protocol for all playback analytics events.
import Analytics

// MARK: - Event Types

/// Marker protocol for all playback analytics events.
public protocol PlaybackAnalyticsEvent: AnalyticsEvent {}

/// Event capturing that playback started.
public struct PlaybackStartedEvent: PlaybackAnalyticsEvent {
    public let name = "play"
    public let reason: String

    public var properties: [String: Any]? {
        ["reason": reason]
    }

    public init(reason: String) {
        self.reason = reason
    }
}

/// Event capturing that playback stopped.
public struct PlaybackStoppedEvent: PlaybackAnalyticsEvent {
    public let name = "pause"
    public let reason: String?
    public let duration: TimeInterval

    public var properties: [String: Any]? {
        var props: [String: Any] = ["duration": duration]
        if let reason { props["reason"] = reason }
        return props
    }

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
    public let name = "stall_recovery"

    public let playerType: PlayerControllerType
    public let successful: Bool
    public let attempts: Int
    public let stallDuration: TimeInterval
    public let reason: StallReason
    public let recoveryMethod: RecoveryMethod
    
    public var properties: [String: Any]? {
        [
            "player_type": playerType.rawValue,
            "successful": successful,
            "attempts": attempts,
            "stall_duration": stallDuration,
            "reason": reason.rawValue,
            "recovery_method": recoveryMethod.rawValue
        ]
    }

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
    public let name = "interruption"
    public let type: InterruptionType
    
    public var properties: [String: Any]? {
        ["type": type.rawValue]
    }

    public init(type: InterruptionType) {
        self.type = type
    }
}

/// Event capturing an error during playback.
public struct ErrorEvent: PlaybackAnalyticsEvent {
    public let name = "error"
    public let error: String
    public let context: String
    
    public var properties: [String: Any]? {
        ["error": error, "context": context]
    }

    public init(error: Error, context: String) {
        self.error = error.localizedDescription
        self.context = context
    }

    public init(error: String, context: String) {
        self.error = error
        self.context = context
    }
}

public struct CPUUsageEvent: PlaybackAnalyticsEvent {
    public let name = "cpu_usage"
    public let playerType: PlayerControllerType
    public let cpuUsage: Double
    
    public var properties: [String: Any]? {
        [
            "player_type": playerType.rawValue,
            "cpu_usage": cpuUsage
        ]
    }

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
    public let name = "cpu_session"
    
    public let playerType: PlayerControllerType
    public let context: PlaybackContext
    public let endReason: CPUSessionEndReason
    public let averageCPU: Double
    public let maxCPU: Double
    public let sampleCount: Int
    public let durationSeconds: TimeInterval
    
    public var properties: [String: Any]? {
        [
            "player_type": playerType.rawValue,
            "context": context.rawValue,
            "end_reason": endReason.rawValue,
            "average_cpu": averageCPU,
            "max_cpu": maxCPU,
            "sample_count": sampleCount,
            "duration_seconds": durationSeconds
        ]
    }

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
