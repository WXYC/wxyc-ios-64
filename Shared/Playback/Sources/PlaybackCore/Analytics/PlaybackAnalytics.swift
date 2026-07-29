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
    public static let name = "play"
    public let reason: String
    /// The clean, low-cardinality attribution surface (#668) — e.g. `.carPlay`,
    /// `.siri`, `.widget` — derived from the `PlaybackReason` at the call site
    /// via `PlaybackReason.playbackSource`. Supersedes the old call-site
    /// `source` string (a `#function` call-site name) that PostHog received
    /// before the analytics-architecture unification and that every event
    /// since has shipped as `null`; see `PlaybackSource`. Defaults to
    /// `.unknown` for the lower player-implementation layers (MP3Streamer,
    /// HLSPlayer, RadioPlayer) that emit their own diagnostic `play` events
    /// without a `PlaybackReason` in scope.
    public let source: PlaybackSource
    /// The stable per-listen identifier (#665) active when this event fired,
    /// so a `play` intent can be joined back to the listen it belongs to.
    /// `nil` at call sites that don't yet have a controller-tracked session
    /// (e.g. the lower player-implementation layers).
    public let sessionID: String?

    public var properties: [String: Any]? {
        var props: [String: Any] = ["reason": reason, "source": source.rawValue]
        if let sessionID { props["session_id"] = sessionID }
        return props
    }

    public init(reason: String, source: PlaybackSource = .unknown, sessionID: String? = nil) {
        self.reason = reason
        self.source = source
        self.sessionID = sessionID
    }
}

/// Event capturing that playback actually began rendering audio.
///
/// This is the success counterpart to `PlaybackStartedEvent` (name `"play"`, the
/// *intent*): `PlaybackStartedEvent` counts every attempt, while this event —
/// name `"first_audio"` — fires exactly once per start, only when the stream
/// first crosses into `.playing` with audio rendering. Paired with the `play`
/// intent count it yields a start-success rate; paired with `time_to_first_audio`
/// it yields a start-latency distribution. It does not re-fire on stall/reconnect
/// recovery (that is what `stall_recovery` tracks), so it stays a clean
/// denominator for `stream_error`.
///
/// Player-agnostic: emitted from the shared `AudioPlayerInternalEvent.firstAudio`
/// forwarding path, so MP3Streamer / HLS / any future player report it identically.
public struct PlaybackFirstAudioEvent: PlaybackAnalyticsEvent {
    public static let name = "first_audio"
    /// The player that produced the audio.
    public let playerType: PlayerControllerType
    /// Seconds elapsed from the play intent to first rendered audio.
    public let timeToFirstAudio: TimeInterval
    /// The stable per-listen identifier (#665) active when this event fired.
    public let sessionID: String?

    public var properties: [String: Any]? {
        var props: [String: Any] = [
            "player_type": playerType.rawValue,
            "time_to_first_audio": timeToFirstAudio
        ]
        if let sessionID { props["session_id"] = sessionID }
        return props
    }

    public init(playerType: PlayerControllerType, timeToFirstAudio: TimeInterval, sessionID: String? = nil) {
        self.playerType = playerType
        self.timeToFirstAudio = timeToFirstAudio
        self.sessionID = sessionID
    }
}

/// Event capturing that playback stopped.
public struct PlaybackStoppedEvent: PlaybackAnalyticsEvent {
    public static let name = "pause"
    public let reason: String?
    /// The clean, low-cardinality attribution surface (#668) for this pause —
    /// see `PlaybackStartedEvent.source` / `PlaybackSource` for the full
    /// rationale. Unlike `reason`, this is never nil: every call site knows
    /// (or can derive) a `PlaybackReason` for the stop even when it
    /// deliberately withholds the free-text `reason` for a user-initiated
    /// pause (see `AudioPlayerController.toggle(reason:)`), so `source` is
    /// what closes the "user pauses carry no attribution" gap.
    public let source: PlaybackSource
    public let duration: TimeInterval
    /// The stable per-listen identifier (#665) active when this event fired.
    public let sessionID: String?

    public var properties: [String: Any]? {
        var props: [String: Any] = ["duration": duration, "source": source.rawValue]
        if let reason { props["reason"] = reason }
        if let sessionID { props["session_id"] = sessionID }
        return props
    }

    public init(reason: String? = nil, source: PlaybackSource = .unknown, duration: TimeInterval, sessionID: String? = nil) {
        self.reason = reason
        self.source = source
        self.duration = duration
        self.sessionID = sessionID
    }
}

/// Event capturing that playback is still actively rendering audio, emitted
/// on a fixed cadence for the duration of a listen (#666).
///
/// `play`/`pause` alone under-measure total listening time: the longest
/// sessions — the app swiped away, OS-terminated in the background, or
/// crashed — never fire a `pause`, so they contribute zero recorded
/// duration and skew the duration metric toward clean stops
/// (survivorship bias). This event closes that gap: listening-hours and a
/// killed session's duration can both be reconstructed from
/// `max(cumulative_seconds)` grouped by `session_id`, with no `pause`
/// required.
///
/// Fires only while the controller considers itself genuinely playing (not
/// while loading, stalled, or stopped) — see `AudioPlayerController` /
/// `RadioPlayerController` for exactly which state transitions start and
/// stop the cadence.
public struct PlaybackHeartbeatEvent: PlaybackAnalyticsEvent {
    public static let name = "playback_heartbeat"
    /// The stable per-listen identifier (#665) this heartbeat belongs to, so
    /// a run of heartbeats (and, for a killed session, the last one before
    /// the process disappears) can be grouped back into the listen they
    /// measure.
    public let sessionID: String?
    /// Elapsed playing time since the play intent, read from the same
    /// monotonic `Core.Timer` (`ContinuousClock`) source as `pause.duration`
    /// (#667) — so the two metrics agree, and the last heartbeat before a
    /// kill is directly usable as that listen's duration.
    public let cumulativeSeconds: TimeInterval
    /// Whether the app was foregrounded or backgrounded when this heartbeat fired.
    public let context: PlaybackContext
    /// The player implementation producing the audio.
    public let playerType: PlayerControllerType

    public var properties: [String: Any]? {
        var props: [String: Any] = [
            "cumulative_seconds": cumulativeSeconds,
            "context": context.rawValue,
            "player_type": playerType.rawValue
        ]
        if let sessionID { props["session_id"] = sessionID }
        return props
    }

    public init(
        sessionID: String?,
        cumulativeSeconds: TimeInterval,
        context: PlaybackContext,
        playerType: PlayerControllerType
    ) {
        self.sessionID = sessionID
        self.cumulativeSeconds = cumulativeSeconds
        self.context = context
        self.playerType = playerType
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
    /// Recovered inside the uncapped reconnect holding pattern because the
    /// injected network-reachability signal crossed to `→ satisfied` and
    /// accelerated a pending reconnect (as opposed to waiting out the timed
    /// cadence). Attribution for the reachability gate added in #517.
    case reachabilityResume = "reachability_resume"
    /// Recovered inside the uncapped reconnect holding pattern via its flat
    /// timed *fallback* cadence — either no reachability signal is wired, or the
    /// path was already satisfied and the connect simply succeeded on a later
    /// tick. The complement of `reachabilityResume`; see #517.
    case holdingFallback = "holding_fallback"
}

/// Event capturing recovery from a stall.
public struct StallRecoveryEvent: PlaybackAnalyticsEvent {
    public static let name = "stall_recovery"
    public let playerType: PlayerControllerType
    public let successful: Bool
    public let attempts: Int
    public let stallDuration: TimeInterval
    public let reason: StallReason
    public let recoveryMethod: RecoveryMethod
    /// The stable per-listen identifier (#665) active when this event fired,
    /// so a stall/recovery pair can be attributed to the listen it interrupted.
    public let sessionID: String?

    public var properties: [String: Any]? {
        var props: [String: Any] = [
            "player_type": playerType.rawValue,
            "successful": successful,
            "attempts": attempts,
            "stall_duration": stallDuration,
            "reason": reason.rawValue,
            "recovery_method": recoveryMethod.rawValue
        ]
        if let sessionID { props["session_id"] = sessionID }
        return props
    }

    public init(
        playerType: PlayerControllerType,
        successful: Bool = true,
        attempts: Int,
        stallDuration: TimeInterval,
        reason: StallReason = .bufferUnderrun,
        recoveryMethod: RecoveryMethod = .bufferRefill,
        sessionID: String? = nil
    ) {
        self.playerType = playerType
        self.successful = successful
        self.attempts = attempts
        self.stallDuration = stallDuration
        self.reason = reason
        self.recoveryMethod = recoveryMethod
        self.sessionID = sessionID
    }
}

/// Type of stream error that occurred.
public enum StreamErrorType: String, Sendable, Equatable {
    /// All reconnection attempts with exponential backoff exhausted
    case backoffExhausted = "backoff_exhausted"
    /// Connected, but playback never began within the startup deadline (starved mid-buffering)
    case startupTimeout = "startup_timeout"
    /// Playback was intended but no audio and no other error signal arrived
    /// within the whole play-intent→first-audio window — the fully-silent
    /// startup class (session-activation abort, deferred connect never ran,
    /// `'!int'` retries exhausted). Distinct from `startupTimeout`, which
    /// presupposes a connection was established. See #518.
    case silentStartup = "silent_startup"
    /// Network connectivity error
    case networkError = "network_error"
    /// Audio decoding failed
    case decodingError = "decoding_error"
    /// Player-level error (AVPlayer, AudioEngine, etc.)
    case playerError = "player_error"
    /// The audio session could not be activated because another app's audio
    /// could not be interrupted (AVAudioSession `CannotInterruptOthers`, FourCC
    /// `'!int'`). Distinct from buffer starvation: this is a session
    /// (re)activation failure, typically around foreground/background
    /// transitions and rapid play/pause. See #514.
    case sessionActivationConflict = "session_activation_conflict"
    /// Unclassified error
    case unknown = "unknown"
}

/// Event capturing a stream error that could not be recovered from.
///
/// This event complements `StallRecoveryEvent`: while stall recovery tracks successful
/// recoveries, this event captures failures where playback could not be restored.
public struct StreamErrorEvent: PlaybackAnalyticsEvent {
    public static let name = "stream_error"
    /// The type of player controller that experienced the error
    public let playerType: PlayerControllerType
    /// Classification of the error
    public let errorType: StreamErrorType
    /// Human-readable error description
    public let errorDescription: String
    /// Number of reconnection attempts made before giving up
    public let reconnectAttempts: Int
    /// How long playback was active before the error
    public let sessionDuration: TimeInterval
    /// Duration of preceding stall (if error occurred during recovery)
    public let stallDuration: TimeInterval?
    /// What recovery method was attempted
    public let recoveryMethod: RecoveryMethod
    /// The stable per-listen identifier (#665) active when this event fired.
    public let sessionID: String?

    public var properties: [String: Any]? {
        var props: [String: Any] = [
            "player_type": playerType.rawValue,
            "error_type": errorType.rawValue,
            "error_description": errorDescription,
            "reconnect_attempts": reconnectAttempts,
            "session_duration": sessionDuration,
            "recovery_method": recoveryMethod.rawValue
        ]
        if let stallDuration {
            props["stall_duration"] = stallDuration
        }
        if let sessionID {
            props["session_id"] = sessionID
        }
        return props
    }

    public init(
        playerType: PlayerControllerType,
        errorType: StreamErrorType,
        errorDescription: String,
        reconnectAttempts: Int,
        sessionDuration: TimeInterval,
        stallDuration: TimeInterval? = nil,
        recoveryMethod: RecoveryMethod = .retryWithBackoff,
        sessionID: String? = nil
    ) {
        self.playerType = playerType
        self.errorType = errorType
        self.errorDescription = errorDescription
        self.reconnectAttempts = reconnectAttempts
        self.sessionDuration = sessionDuration
        self.stallDuration = stallDuration
        self.recoveryMethod = recoveryMethod
        self.sessionID = sessionID
    }
}

/// Event capturing that the connect-path startup watchdog deferred repeatedly
/// while parked waiting for network connectivity (the #697 gate) — an extended
/// offline park rather than a brief blip. Deliberately distinct from
/// `StreamErrorEvent`/`startup_timeout`: #697's whole point is that a
/// legitimately offline park is NOT a stream error, but that traded a
/// mislabeled failure for a totally silent multi-minute hang. This event
/// closes that observability gap without inflating the error/timeout signals.
/// Low-rate by construction: fired at most once per park episode, not once
/// per watchdog re-arm (~every `startupTimeout` seconds). See #699.
public struct ExtendedOfflineParkEvent: PlaybackAnalyticsEvent {
    public static let name = "extended_offline_park"
    /// The player that observed the park.
    public let playerType: PlayerControllerType
    /// Seconds elapsed since the park began, as of the moment this event fired
    /// (not necessarily the park's total length — the park may still be
    /// ongoing).
    public let parkDuration: TimeInterval
    /// The stable per-listen identifier (#665) active when this event fired.
    public let sessionID: String?

    public var properties: [String: Any]? {
        var props: [String: Any] = [
            "player_type": playerType.rawValue,
            "park_duration": parkDuration
        ]
        if let sessionID { props["session_id"] = sessionID }
        return props
    }

    public init(playerType: PlayerControllerType, parkDuration: TimeInterval, sessionID: String? = nil) {
        self.playerType = playerType
        self.parkDuration = parkDuration
        self.sessionID = sessionID
    }
}

/// Event capturing an audio session interruption.
public struct InterruptionEvent: PlaybackAnalyticsEvent {
    public static let name = "interruption"
    public let type: InterruptionType
    /// The stable per-listen identifier (#665) active when this event fired.
    /// Interruptions preserve the session across the auto-resume path, so
    /// this is expected to match the id on the `play`/`pause` pair that
    /// bracket the interruption.
    public let sessionID: String?

    public var properties: [String: Any]? {
        var props: [String: Any] = ["type": type.rawValue]
        if let sessionID { props["session_id"] = sessionID }
        return props
    }

    public init(type: InterruptionType, sessionID: String? = nil) {
        self.type = type
        self.sessionID = sessionID
    }
}

public struct CPUUsageEvent: PlaybackAnalyticsEvent {
    public static let name = "cpu_usage"
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
    public static let name = "cpu_session"
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
