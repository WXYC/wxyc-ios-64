import Foundation

// MARK: - Flush Reason

/// Reason for flushing aggregated metrics.
public enum QualityFlushReason: String, Sendable {
    /// App is entering background
    case background
    /// User switched to a different shader
    case shaderChanged
    /// Periodic checkpoint (every 5 minutes)
    case periodic
}

// MARK: - Session Outcome

/// Classification of how a thermal session concluded.
public enum QualitySessionOutcome: String, Sendable {
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
public protocol QualityAnalyticsEvent: Sendable, Equatable {}

/// Event captured on each optimization tick (aggregated, not sent directly).
public struct QualityAdjustmentEvent: QualityAnalyticsEvent {
    /// Identifier for the active shader
    public let shaderId: String
    /// Current wallpaper FPS setting (display rate)
    public let wallpaperFPS: Float
    /// Current scale setting
    public let scale: Float
    /// Current level of detail setting
    public let lod: Float
    /// Raw thermal state from system
    public let thermalState: ProcessInfo.ThermalState
    /// Current thermal momentum
    public let momentum: Float
    /// Whether frame interpolation is currently enabled
    public let interpolationEnabled: Bool
    /// Shader execution FPS (differs from wallpaperFPS when interpolating)
    public let shaderFPS: Float
    /// When this adjustment occurred
    public let timestamp: Date

    public init(
        shaderId: String,
        wallpaperFPS: Float,
        scale: Float,
        lod: Float,
        thermalState: ProcessInfo.ThermalState,
        momentum: Float,
        interpolationEnabled: Bool = false,
        shaderFPS: Float? = nil,
        timestamp: Date = Date()
    ) {
        self.shaderId = shaderId
        self.wallpaperFPS = wallpaperFPS
        self.scale = scale
        self.lod = lod
        self.thermalState = thermalState
        self.momentum = momentum
        self.interpolationEnabled = interpolationEnabled
        self.shaderFPS = shaderFPS ?? wallpaperFPS
        self.timestamp = timestamp
    }
}

// MARK: - Session Summary

/// Aggregated metrics for a thermal optimization session.
///
/// This is what gets sent to PostHog, not individual adjustment events.
public struct QualitySessionSummary: Sendable, Equatable {

    // MARK: Identity

    /// Identifier for the shader
    public let shaderId: String
    /// Why this summary was flushed
    public let flushReason: QualityFlushReason

    // MARK: Quality Delivered

    /// Average wallpaper FPS over the session
    public let avgWallpaperFPS: Float
    /// Average scale over the session
    public let avgScale: Float
    /// Average level of detail over the session
    public let avgLOD: Float
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
    /// Sessions taken to reach stability (from AdaptiveProfile)
    public let sessionsToStability: Int?
    /// Classification of how the session concluded
    public let sessionOutcome: QualitySessionOutcome
    /// Final wallpaper FPS when stability was reached (nil if not stabilized)
    public let stableWallpaperFPS: Float?
    /// Final scale when stability was reached (nil if not stabilized)
    public let stableScale: Float?
    /// Final LOD when stability was reached (nil if not stabilized)
    public let stableLOD: Float?

    // MARK: Frame Interpolation

    /// Percentage of session time with interpolation enabled (0-100)
    public let interpolationEnabledPercent: Float
    /// Average shader FPS while interpolating (nil if never interpolated)
    public let avgShaderFPSWhileInterpolating: Float?
    /// Number of times interpolation was activated during session
    public let interpolationActivationCount: Int
    /// Estimated shader workload reduction from interpolation (0-100%)
    public let estimatedWorkloadReductionPercent: Float
    /// Number of interpolator resets (potential visual glitches)
    public let interpolatorResetCount: Int

    public init(
        shaderId: String,
        flushReason: QualityFlushReason,
        avgWallpaperFPS: Float,
        avgScale: Float,
        avgLOD: Float,
        sessionDurationSeconds: TimeInterval,
        timeInCriticalSeconds: TimeInterval,
        throttleEventCount: Int,
        oscillationCount: Int,
        reachedStability: Bool,
        sessionsToStability: Int?,
        sessionOutcome: QualitySessionOutcome,
        stableWallpaperFPS: Float?,
        stableScale: Float?,
        stableLOD: Float?,
        interpolationEnabledPercent: Float = 0,
        avgShaderFPSWhileInterpolating: Float? = nil,
        interpolationActivationCount: Int = 0,
        estimatedWorkloadReductionPercent: Float = 0,
        interpolatorResetCount: Int = 0
    ) {
        self.shaderId = shaderId
        self.flushReason = flushReason
        self.avgWallpaperFPS = avgWallpaperFPS
        self.avgScale = avgScale
        self.avgLOD = avgLOD
        self.sessionDurationSeconds = sessionDurationSeconds
        self.timeInCriticalSeconds = timeInCriticalSeconds
        self.throttleEventCount = throttleEventCount
        self.oscillationCount = oscillationCount
        self.reachedStability = reachedStability
        self.sessionsToStability = sessionsToStability
        self.sessionOutcome = sessionOutcome
        self.stableWallpaperFPS = stableWallpaperFPS
        self.stableScale = stableScale
        self.stableLOD = stableLOD
        self.interpolationEnabledPercent = interpolationEnabledPercent
        self.avgShaderFPSWhileInterpolating = avgShaderFPSWhileInterpolating
        self.interpolationActivationCount = interpolationActivationCount
        self.estimatedWorkloadReductionPercent = estimatedWorkloadReductionPercent
        self.interpolatorResetCount = interpolatorResetCount
    }
}

// MARK: - QualityAnalytics Protocol

/// Protocol for capturing thermal optimization events.
///
/// Implementations aggregate adjustment events in memory and flush
/// session summaries to analytics on session boundaries.
@MainActor
public protocol QualityAnalytics: AnyObject {

    /// Records an optimization tick event (aggregated in memory).
    ///
    /// Called frequently (every 5 seconds) but not sent to analytics directly.
    func record(_ event: QualityAdjustmentEvent)

    /// Flushes aggregated metrics to analytics.
    ///
    /// Called on session boundaries (background, shader change, periodic).
    func flush(reason: QualityFlushReason)
}

