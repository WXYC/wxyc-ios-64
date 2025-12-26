//
//  PlaybackAnalytics.swift
//  PlaybackCore
//
//  Unified analytics protocol for playback events.
//  Replaces the scattered AudioAnalyticsProtocol and PlaybackMetricsReporter.
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
    /// Why playback was initiated
    public let reason: PlaybackStartReason

    public init(reason: PlaybackStartReason) {
        self.reason = reason
    }
}

/// Event capturing that playback stopped.
public struct PlaybackStoppedEvent: PlaybackAnalyticsEvent {
    /// Why playback was stopped
    public let reason: PlaybackStopReason
    /// How long playback lasted in seconds
    public let duration: TimeInterval

    public init(reason: PlaybackStopReason, duration: TimeInterval) {
        self.reason = reason
        self.duration = duration
    }
}

/// Event capturing recovery from a stall.
public struct StallRecoveryEvent: PlaybackAnalyticsEvent {
    /// Number of reconnection attempts before recovery
    public let attempts: Int
    /// How long the stall lasted in seconds
    public let stallDuration: TimeInterval

    public init(attempts: Int, stallDuration: TimeInterval) {
        self.attempts = attempts
        self.stallDuration = stallDuration
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
}
