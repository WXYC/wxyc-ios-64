import Foundation

/// Represents the current quality level based on thermal state.
///
/// As the device heats up, the throttle level worsens from `.nominal` to `.critical`,
/// reducing resolution and frame rate to lower GPU load.
public enum ThermalThrottleLevel: Int, Sendable, Equatable, Comparable, CaseIterable {
    case nominal = 0
    case fair = 1
    case serious = 2
    case critical = 3

    /// Display name for UI.
    public var displayName: String {
        switch self {
        case .nominal: "Nominal (100% @ 60fps)"
        case .fair: "Fair (75% @ 60fps)"
        case .serious: "Serious (50% @ 30fps)"
        case .critical: "Critical (50% @ 15fps)"
        }
    }

    /// The resolution scale factor for this throttle level.
    ///
    /// Lower values mean rendering at a smaller resolution and upscaling.
    public var resolutionScale: Float {
        switch self {
        case .nominal: 1.0
        case .fair: 0.75
        case .serious: 0.5
        case .critical: 0.5
        }
    }

    /// The target frames per second for this throttle level.
    public var targetFPS: Int {
        switch self {
        case .nominal: 60
        case .fair: 60
        case .serious: 30
        case .critical: 15
        }
    }

    /// Creates a throttle level from the system's thermal state.
    public init(thermalState: ProcessInfo.ThermalState) {
        switch thermalState {
        case .nominal:
            self = .nominal
        case .fair:
            self = .fair
        case .serious:
            self = .serious
        case .critical:
            self = .critical
        @unknown default:
            self = .nominal
        }
    }

    /// Returns `true` if this level represents a worse (more throttled) state than the other.
    public func isWorseThan(_ other: ThermalThrottleLevel) -> Bool {
        rawValue > other.rawValue
    }

    /// Returns `true` if this level represents a better (less throttled) state than the other.
    public func isBetterThan(_ other: ThermalThrottleLevel) -> Bool {
        rawValue < other.rawValue
    }

    /// The next better (less throttled) level, or `.nominal` if already at best.
    public var nextBetterLevel: ThermalThrottleLevel {
        switch self {
        case .nominal: .nominal
        case .fair: .nominal
        case .serious: .fair
        case .critical: .serious
        }
    }

    public static func < (lhs: ThermalThrottleLevel, rhs: ThermalThrottleLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
