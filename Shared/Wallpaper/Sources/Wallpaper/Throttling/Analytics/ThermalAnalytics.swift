import Foundation

// MARK: - Flush Reason

/// Reason for flushing aggregated metrics.
public enum ThermalFlushReason: String, Sendable {
    /// App is entering background
    case background
    /// User switched to a different shader
    case shaderChanged
    /// Periodic checkpoint (every 5 minutes)
    case periodic
}

// MARK: - Session Outcome

/// Classification of how a thermal session concluded.
public enum ThermalSessionOutcome: String, Sendable {
    /// Session was too brief (< 30s) to meaningfully optimize
    case tooBrief
    /// Shader is efficient enough that throttling was never needed
    case neverThrottled
    /// Profile was already optimized from previous sessions, stayed stable
    case alreadyOptimized
    /// Had to throttle this session, reached stability
    case optimizedThisSession
    /// Session ended before reaching stable optimization
    case stillOptimizing
}

// MARK: - Event Types

/// Marker protocol for all thermal analytics events.
public protocol ThermalAnalyticsEvent: Sendable, Equatable {}

/// Event captured on each optimization tick (aggregated, not sent directly).
public struct ThermalAdjustmentEvent: ThermalAnalyticsEvent {
    /// Identifier for the active shader
    public let shaderId: String
    /// Current FPS setting
    public let fps: Float
    /// Current scale setting
    public let scale: Float
    /// Raw thermal state from system
    public let thermalState: ProcessInfo.ThermalState
    /// Current thermal momentum
    public let momentum: Float
    /// When this adjustment occurred
    public let timestamp: Date

    public init(
        shaderId: String,
        fps: Float,
        scale: Float,
        thermalState: ProcessInfo.ThermalState,
        momentum: Float,
        timestamp: Date = Date()
    ) {
        self.shaderId = shaderId
        self.fps = fps
        self.scale = scale
        self.thermalState = thermalState
        self.momentum = momentum
        self.timestamp = timestamp
    }
}

// MARK: - Session Summary

/// Aggregated metrics for a thermal optimization session.
///
/// This is what gets sent to PostHog, not individual adjustment events.
public struct ThermalSessionSummary: Sendable, Equatable {

    // MARK: Identity

    /// Identifier for the shader
    public let shaderId: String
    /// Why this summary was flushed
    public let flushReason: ThermalFlushReason

    // MARK: Quality Delivered

    /// Average FPS over the session
    public let avgFPS: Float
    /// Average scale over the session
    public let avgScale: Float
    /// How long this session lasted
    public let sessionDurationSeconds: TimeInterval

    // MARK: Thermal Health

    /// Time spent in critical thermal state
    public let timeInCriticalSeconds: TimeInterval
    /// Number of times quality was reduced
    public let throttleEventCount: Int
    /// Number of direction changes (potential oscillation)
    public let oscillationCount: Int

    // MARK: Convergence

    /// Whether optimization reached a stable point
    public let reachedStability: Bool
    /// Sessions taken to reach stability (from ThermalProfile)
    public let sessionsToStability: Int?
    /// Classification of how the session concluded
    public let sessionOutcome: ThermalSessionOutcome

    public init(
        shaderId: String,
        flushReason: ThermalFlushReason,
        avgFPS: Float,
        avgScale: Float,
        sessionDurationSeconds: TimeInterval,
        timeInCriticalSeconds: TimeInterval,
        throttleEventCount: Int,
        oscillationCount: Int,
        reachedStability: Bool,
        sessionsToStability: Int?,
        sessionOutcome: ThermalSessionOutcome
    ) {
        self.shaderId = shaderId
        self.flushReason = flushReason
        self.avgFPS = avgFPS
        self.avgScale = avgScale
        self.sessionDurationSeconds = sessionDurationSeconds
        self.timeInCriticalSeconds = timeInCriticalSeconds
        self.throttleEventCount = throttleEventCount
        self.oscillationCount = oscillationCount
        self.reachedStability = reachedStability
        self.sessionsToStability = sessionsToStability
        self.sessionOutcome = sessionOutcome
    }
}

// MARK: - ThermalAnalytics Protocol

/// Protocol for capturing thermal optimization events.
///
/// Implementations aggregate adjustment events in memory and flush
/// session summaries to analytics on session boundaries.
@MainActor
public protocol ThermalAnalytics: AnyObject {

    /// Records an optimization tick event (aggregated in memory).
    ///
    /// Called frequently (every 5 seconds) but not sent to analytics directly.
    func record(_ event: ThermalAdjustmentEvent)

    /// Flushes aggregated metrics to analytics.
    ///
    /// Called on session boundaries (background, shader change, periodic).
    func flush(reason: ThermalFlushReason)
}
