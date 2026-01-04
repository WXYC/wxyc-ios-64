import Foundation

/// Tracks thermal state history and computes momentum using exponential moving average.
///
/// Momentum indicates the rate and direction of thermal change:
/// - Positive momentum (> 0.1): device is heating up
/// - Negative momentum (< -0.1): device is cooling down
/// - Near zero (within dead zone): thermal state is stable
public struct ThermalSignal: Sendable {

    /// Threshold for considering the signal stable (dead zone).
    public static let deadZone: Float = 0.1

    /// EMA smoothing factor (0-1). Higher values respond faster to changes.
    public static let smoothingFactor: Float = 0.3

    /// Current thermal momentum (-1.0 to 1.0).
    public private(set) var momentum: Float = 0

    /// Last recorded thermal state.
    public private(set) var lastState: ProcessInfo.ThermalState?

    /// Timestamp of last update.
    public private(set) var lastUpdate: Date?

    public init() {}

    /// The current thermal trend based on momentum.
    public var trend: ThermalTrend {
        if momentum > Self.deadZone {
            return .heating
        } else if momentum < -Self.deadZone {
            return .cooling
        } else {
            return .stable
        }
    }

    /// Records a new thermal state reading and updates momentum.
    ///
    /// - Parameter state: The current thermal state from ProcessInfo.
    public mutating func record(_ state: ProcessInfo.ThermalState) {
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
    }

    /// Resets the signal to initial state.
    ///
    /// Call this when resuming from background, as thermal state during
    /// background is unknown.
    public mutating func reset() {
        momentum = 0
        lastState = nil
        lastUpdate = nil
    }
}

// MARK: - ThermalTrend

/// The direction of thermal change.
public enum ThermalTrend: Sendable {
    /// Device is heating up (momentum > dead zone).
    case heating

    /// Device is cooling down (momentum < -dead zone).
    case cooling

    /// Thermal state is stable (momentum within dead zone).
    case stable
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
