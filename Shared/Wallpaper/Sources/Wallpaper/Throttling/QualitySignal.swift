//
//  QualitySignal.swift
//  Wallpaper
//
//  Tracks thermal state history using exponential moving average to compute momentum,
//  enabling adaptive quality adjustment based on device heating/cooling trends.
//
//  Created by Jake Bromberg on 01/03/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Tracks thermal state history and computes momentum using exponential moving average.
///
/// Momentum indicates the rate and direction of thermal change:
/// - Positive momentum (> 0.1): device is heating up
/// - Negative momentum (< -0.1): device is cooling down
/// - Near zero (within dead zone): thermal state is stable
struct QualitySignal: Sendable {

    /// Threshold for considering the signal stable (dead zone).
    static let deadZone: Float = 0.1

    /// Momentum threshold for entering heating state (prevents rapid oscillation).
    static let heatingEntryThreshold: Float = 0.15

    /// Momentum threshold for exiting heating state (creates hysteresis gap).
    static let heatingExitThreshold: Float = 0.05

    /// Momentum threshold for entering cooling state (prevents rapid oscillation).
    static let coolingEntryThreshold: Float = -0.15

    /// Momentum threshold for exiting cooling state (creates hysteresis gap).
    static let coolingExitThreshold: Float = -0.05

    /// EMA smoothing factor (0-1). Higher values respond faster to changes.
    static let smoothingFactor: Float = 0.3

    /// EMA smoothing factor for recovery magnitude tracking (slower than momentum).
    static let recoveryMagnitudeSmoothing: Float = 0.2

    /// Decay rate for recovery magnitude when not actively cooling.
    static let recoveryMagnitudeDecay: Float = 0.8

    /// Current thermal momentum (-1.0 to 1.0).
    private(set) var momentum: Float = 0

    /// Magnitude of cooling rate for proportional recovery scaling (0.0+).
    ///
    /// Tracks how quickly the device is cooling down. Higher values indicate
    /// rapid cooling and enable faster quality recovery. Uses a separate EMA
    /// with slower smoothing than momentum to avoid jitter.
    private(set) var recoveryMagnitude: Float = 0

    /// Current thermal direction state (with hysteresis).
    ///
    /// Uses entry/exit thresholds to prevent rapid state switching at
    /// thermal boundaries. Must exceed entry threshold to commit to a
    /// direction and drop below exit threshold to leave it.
    private(set) var direction: ThermalDirection = .stable

    /// Last recorded thermal state.
    private(set) var lastState: ProcessInfo.ThermalState?

    /// Timestamp of last update.
    private(set) var lastUpdate: Date?

    init() {}

    /// The current thermal trend based on direction with hysteresis.
    ///
    /// Direction is updated in record() to prevent rapid switching at thermal boundaries.
    /// Creates a 0.1 hysteresis gap between entry (±0.15) and exit (±0.05) thresholds.
    var trend: QualityTrend {
        direction.toTrend()
    }

    /// Proportional recovery scale factor based on cooling magnitude (1.0 to 3.0).
    ///
    /// Returns a multiplier for quality recovery steps. Higher values indicate
    /// rapid cooling and enable faster quality restoration:
    /// - 1.0x: minimal or no cooling (baseline recovery speed)
    /// - 2.0x: moderate cooling
    /// - 3.0x: rapid cooling (maximum recovery acceleration)
    var recoveryScale: Float {
        // Scale from 1.0x to 3.0x based on recovery magnitude
        let scale = 1.0 + (recoveryMagnitude * 2.0)
        return min(scale, 3.0)
    }

    /// Records a new thermal state reading and updates momentum.
    ///
    /// - Parameter state: The current thermal state from ProcessInfo.
    mutating func record(_ state: ProcessInfo.ThermalState) {
        defer {
            lastState = state
            lastUpdate = Date()
        }

        guard let previous = lastState else {
            // First reading - if device is already hot, initialize momentum accordingly
            // This ensures we respond immediately to elevated thermal states
            if state != .nominal {
                momentum = state.normalizedValue * Self.smoothingFactor
            }
            return
        }

        // Calculate change as normalized value (-1 to 1)
        let previousValue = previous.normalizedValue
        let currentValue = state.normalizedValue
        let delta = currentValue - previousValue

        // Update momentum using EMA
        momentum = Self.smoothingFactor * delta + (1 - Self.smoothingFactor) * momentum

        // Update recovery magnitude based on cooling rate
        if delta < 0 {
            // Device is cooling - track magnitude for proportional recovery
            let coolingMagnitude = abs(delta)
            recoveryMagnitude = Self.recoveryMagnitudeSmoothing * coolingMagnitude + (1 - Self.recoveryMagnitudeSmoothing) * recoveryMagnitude
        } else {
            // Device heating or stable - decay recovery magnitude
            recoveryMagnitude *= Self.recoveryMagnitudeDecay
        }

        // Update direction state using hysteresis thresholds
        updateDirection()
    }

    /// Updates the thermal direction state using hysteresis thresholds.
    ///
    /// Must be called after momentum is updated to ensure direction tracking
    /// reflects current momentum with appropriate hysteresis gaps.
    private mutating func updateDirection() {
        switch direction {
        case .heating:
            // Must drop below exit threshold to leave heating
            if momentum < Self.heatingExitThreshold {
                direction = .stable
            }
        case .cooling:
            // Must rise above exit threshold to leave cooling
            if momentum > Self.coolingExitThreshold {
                direction = .stable
            }
        case .stable:
            // Must exceed entry threshold to commit to a direction
            if momentum > Self.heatingEntryThreshold {
                direction = .heating
            } else if momentum < Self.coolingEntryThreshold {
                direction = .cooling
            }
        }
    }

    /// Resets the signal to initial state.
    ///
    /// Call this when thermal context is completely unknown and you want
    /// to start fresh (e.g., testing scenarios).
    mutating func reset() {
        momentum = 0
        recoveryMagnitude = 0
        direction = .stable
        lastState = nil
        lastUpdate = nil
    }

    /// Seeds the signal from the current thermal state without requiring history.
    ///
    /// Use this when resuming from background to immediately respond to device
    /// temperature. Unlike `reset()`, this initializes momentum proportionally
    /// to the current thermal level so hot devices start with reduced quality.
    ///
    /// - Parameter state: The current thermal state from ProcessInfo.
    mutating func seedFromCurrentState(_ state: ProcessInfo.ThermalState) {
        // Initialize momentum based on absolute thermal level
        // This ensures we respond immediately to elevated thermal states
        momentum = state.normalizedValue * Self.smoothingFactor
        recoveryMagnitude = 0 // Reset recovery magnitude when seeding
        direction = .stable // Reset to stable direction
        lastState = state
        lastUpdate = Date()
    }
}

// MARK: - QualityTrend

/// The direction of thermal change.
enum QualityTrend: Sendable {
    /// Device is heating up (momentum > dead zone).
    case heating

    /// Device is cooling down (momentum < -dead zone).
    case cooling

    /// Thermal state is stable (momentum within dead zone).
    case stable
}

// MARK: - ThermalDirection

/// Thermal direction state with hysteresis support.
///
/// Used internally by QualitySignal to track committed thermal direction
/// and prevent rapid oscillation at thermal boundaries.
enum ThermalDirection: Sendable {
    /// Device is in heating state (committed).
    case heating

    /// Device is in cooling state (committed).
    case cooling

    /// Device is in stable state (not heating or cooling).
    case stable

    /// Converts thermal direction to quality trend.
    func toTrend() -> QualityTrend {
        switch self {
        case .heating: .heating
        case .cooling: .cooling
        case .stable: .stable
        }
    }
}

// MARK: - ProcessInfo.ThermalState Extension

extension ProcessInfo.ThermalState {

    /// Normalized value for computing thermal changes (0.0 to 1.0).
    var normalizedValue: Float {
        switch self {
        case .nominal:
            0.0
        case .fair:
            0.33
        case .serious:
            0.67
        case .critical:
            1.0
        @unknown default:
            0.5
        }
    }
}
