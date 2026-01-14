//
//  FrameRateMonitor.swift
//  Wallpaper
//
//  Monitors frame rate by sampling frame times periodically.
//  Provides early warning for GPU overload before thermal state changes.
//
//  Created by Jake Bromberg on 01/04/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import QuartzCore

/// Monitors frame rate by sampling frame times and detecting performance drops.
///
/// Frame rate monitoring provides faster feedback than thermal state changes,
/// allowing the optimizer to react to GPU overload within seconds rather than
/// waiting for the system's thermal state to update.
///
/// ## Usage
/// ```swift
/// var monitor = FrameRateMonitor()
///
/// // In render loop, record each frame's duration
/// let startTime = CACurrentMediaTime()
/// // ... render ...
/// let duration = CACurrentMediaTime() - startTime
///
/// if let fps = monitor.recordFrame(duration: duration) {
///     if fps < FrameRateMonitor.lowFPSThreshold {
///         // GPU is struggling, trigger quality reduction
///     }
/// }
/// ```
public struct FrameRateMonitor: Sendable {

    /// Number of frames to sample before computing average FPS.
    public static let sampleSize: Int = 30

    /// FPS threshold below which we consider the GPU struggling.
    /// Set slightly below 60 to account for normal variance.
    public static let lowFPSThreshold: Float = 50.0

    /// FPS threshold below which we consider severe performance issues.
    public static let criticalFPSThreshold: Float = 25.0

    /// Minimum interval between FPS reports to avoid excessive updates.
    public static let reportInterval: TimeInterval = 1.0

    // MARK: - State

    private var frameDurations: [CFTimeInterval] = []
    private var lastReportTime: CFTimeInterval = 0

    public init() {}

    // MARK: - Public API

    /// Records a frame's render duration and returns computed FPS when sample is complete.
    ///
    /// Call this after each frame render with the frame's duration. The method
    /// returns the average FPS once enough samples are collected and the report
    /// interval has elapsed.
    ///
    /// - Parameter duration: The frame's render duration in seconds.
    /// - Returns: Average FPS if sample is complete and report interval elapsed, nil otherwise.
    public mutating func recordFrame(duration: CFTimeInterval) -> Float? {
        frameDurations.append(duration)

        // Only report periodically
        let now = CACurrentMediaTime()
        guard now - lastReportTime >= Self.reportInterval else {
            // Trim buffer if it gets too large
            if frameDurations.count > Self.sampleSize * 2 {
                frameDurations.removeFirst(Self.sampleSize)
            }
            return nil
        }

        // Need enough samples
        guard frameDurations.count >= Self.sampleSize else {
            return nil
        }

        // Compute average FPS from recent samples
        let recentSamples = frameDurations.suffix(Self.sampleSize)
        let avgDuration = recentSamples.reduce(0, +) / Double(recentSamples.count)
        let fps = Float(1.0 / avgDuration)

        // Reset for next period
        frameDurations.removeAll(keepingCapacity: true)
        lastReportTime = now

        return fps
    }

    /// Resets the monitor state.
    ///
    /// Call this when the app returns from background or when switching shaders.
    public mutating func reset() {
        frameDurations.removeAll(keepingCapacity: true)
        lastReportTime = 0
    }

    /// Returns the severity of FPS performance issues.
    ///
    /// - Parameter fps: The measured FPS value.
    /// - Returns: A performance severity level.
    public static func severity(for fps: Float) -> PerformanceSeverity {
        if fps < criticalFPSThreshold {
            return .critical
        } else if fps < lowFPSThreshold {
            return .warning
        } else {
            return .normal
        }
    }
}

// MARK: - PerformanceSeverity

/// Severity level of FPS performance issues.
public enum PerformanceSeverity: Sendable {
    /// FPS is acceptable (>= 50).
    case normal

    /// FPS is below target but not critical (25-50).
    case warning

    /// FPS is critically low (< 25).
    case critical

    /// Momentum boost to apply to thermal signal when FPS drops.
    public var momentumBoost: Float {
        switch self {
        case .normal: 0
        case .warning: 0.15
        case .critical: 0.3
        }
    }
}
