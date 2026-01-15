//
//  QualityAnalytics.swift
//  Wallpaper
//
//  Analytics protocol for quality adjustment events.
//
//  Created by Jake Bromberg on 01/03/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

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

import Analytics

/// Marker protocol for all thermal analytics events.
public protocol QualityAnalyticsEvent: AnalyticsEvent {}

public struct QualityAdjustmentEvent: QualityAnalyticsEvent {
    public let name = "quality_adjustment"

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

    public var properties: [String: Any]? {
        [
            "shader_id": shaderId,
            "wallpaper_fps": wallpaperFPS,
            "scale": scale,
            "lod": lod,
            "thermal_state": thermalState.rawValue,
            "momentum": momentum,
            "interpolation_enabled": interpolationEnabled,
            "shader_fps": shaderFPS,
            "timestamp": timestamp.timeIntervalSince1970
        ]
    }

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

public struct QualitySessionSummary: QualityAnalyticsEvent {
    public let name = "quality_session_summary"

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

    public var properties: [String: Any]? {
        var props: [String: Any] = [
            "shader_id": shaderId,
            "flush_reason": flushReason.rawValue,
            "avg_wallpaper_fps": avgWallpaperFPS,
            "avg_scale": avgScale,
            "avg_lod": avgLOD,
            "session_duration_seconds": sessionDurationSeconds,
            "time_in_critical_seconds": timeInCriticalSeconds,
            "throttle_event_count": throttleEventCount,
            "oscillation_count": oscillationCount,
            "reached_stability": reachedStability,
            "session_outcome": sessionOutcome.rawValue,
            "interpolation_enabled_percent": interpolationEnabledPercent,
            "interpolation_activation_count": interpolationActivationCount,
            "estimated_workload_reduction_percent": estimatedWorkloadReductionPercent,
            "interpolator_reset_count": interpolatorResetCount
        ]
        
        if let sessionsToStability { props["sessions_to_stability"] = sessionsToStability }
        if let stableWallpaperFPS { props["stable_wallpaper_fps"] = stableWallpaperFPS }
        if let stableScale { props["stable_scale"] = stableScale }
        if let stableLOD { props["stable_lod"] = stableLOD }
        if let avgShaderFPSWhileInterpolating { props["avg_shader_fps_while_interpolating"] = avgShaderFPSWhileInterpolating }
        
        return props
    }

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
@available(*, deprecated, message: "Use AnalyticsService instead")
public protocol QualityAnalytics: AnyObject {
    func record(_ event: QualityAdjustmentEvent)
    func flush(reason: QualityFlushReason)
}
