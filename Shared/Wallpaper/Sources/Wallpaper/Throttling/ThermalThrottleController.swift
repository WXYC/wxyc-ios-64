import Foundation

/// Monitors thermal state and manages quality throttling with hysteresis for recovery.
///
/// The controller immediately downgrades quality when thermal state worsens,
/// but waits for a hysteresis delay before upgrading when thermal state improves.
/// Quality is restored one level at a time to prevent oscillation.
@Observable
@MainActor
public final class ThermalThrottleController {

    /// Shared instance using the system's thermal state.
    public static let shared = ThermalThrottleController()

    /// Current effective throttle level (with hysteresis applied).
    /// When `debugOverrideLevel` is set, returns the override instead.
    public var currentLevel: ThermalThrottleLevel {
        debugOverrideLevel ?? _currentLevel
    }

    /// Internal current level (without debug override).
    private var _currentLevel: ThermalThrottleLevel = .nominal

    /// Debug override for throttle level. Set to nil to use automatic thermal-based throttling.
    public var debugOverrideLevel: ThermalThrottleLevel?

    /// Raw thermal state from system (for debug display).
    public private(set) var rawThermalState: ProcessInfo.ThermalState = .nominal

    /// Provider for thermal state (injectable for testing).
    private let thermalStateProvider: () -> ProcessInfo.ThermalState

    /// Hysteresis delay before ramping quality back up.
    private let hysteresisDelay: TimeInterval

    /// Time when thermal state last improved (for hysteresis).
    private var lastImprovementTime: Date?

    /// Timer for periodic thermal state checks.
    private var thermalTimer: Timer?

    /// Timer for hysteresis recovery checks.
    private var hysteresisTimer: Timer?

    /// Creates a controller with injectable dependencies for testing.
    ///
    /// - Parameters:
    ///   - thermalStateProvider: Closure returning current thermal state.
    ///   - hysteresisDelay: Seconds to wait before upgrading quality after cooling.
    ///   - startMonitoringAutomatically: Whether to start polling immediately.
    public init(
        thermalStateProvider: @escaping () -> ProcessInfo.ThermalState = { ProcessInfo.processInfo.thermalState },
        hysteresisDelay: TimeInterval = 30.0,
        startMonitoringAutomatically: Bool = true
    ) {
        self.thermalStateProvider = thermalStateProvider
        self.hysteresisDelay = hysteresisDelay

        // Initialize with current state
        updateThermalState()

        if startMonitoringAutomatically {
            startMonitoring()
        }
    }

    /// Starts periodic thermal monitoring.
    public func startMonitoring() {
        stopMonitoring()

        thermalTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkThermalState()
            }
        }

        // Initial check
        checkThermalState()
    }

    /// Stops periodic thermal monitoring.
    public func stopMonitoring() {
        thermalTimer?.invalidate()
        thermalTimer = nil
        hysteresisTimer?.invalidate()
        hysteresisTimer = nil
    }

    /// Checks thermal state and updates throttle level.
    ///
    /// Immediately downgrades on worsening, starts hysteresis timer on improvement.
    public func checkThermalState() {
        updateThermalState()
    }

    /// Checks if hysteresis period has elapsed and upgrades if appropriate.
    public func checkHysteresisRecovery() {
        guard let improvementTime = lastImprovementTime else { return }

        let elapsed = Date().timeIntervalSince(improvementTime)
        if elapsed >= hysteresisDelay {
            let targetLevel = ThermalThrottleLevel(thermalState: rawThermalState)
            if targetLevel.isBetterThan(_currentLevel) {
                // Step up one level
                _currentLevel = _currentLevel.nextBetterLevel

                // If still not at target, schedule another check
                if _currentLevel != targetLevel {
                    lastImprovementTime = Date()
                    scheduleHysteresisCheck()
                } else {
                    lastImprovementTime = nil
                    cancelHysteresisTimer()
                }
            }
        }
    }

    // MARK: - Private

    private func updateThermalState() {
        let newState = thermalStateProvider()
        let newLevel = ThermalThrottleLevel(thermalState: newState)

        rawThermalState = newState

        if newLevel.isWorseThan(_currentLevel) {
            // Immediate downgrade
            _currentLevel = newLevel
            lastImprovementTime = nil
            cancelHysteresisTimer()
        } else if newLevel.isBetterThan(_currentLevel) {
            // Start or continue hysteresis timer
            if lastImprovementTime == nil {
                lastImprovementTime = Date()
                scheduleHysteresisCheck()
            }
        }
        // If equal, no action needed
    }

    private func scheduleHysteresisCheck() {
        cancelHysteresisTimer()

        hysteresisTimer = Timer.scheduledTimer(withTimeInterval: hysteresisDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.checkHysteresisRecovery()
            }
        }
    }

    private func cancelHysteresisTimer() {
        hysteresisTimer?.invalidate()
        hysteresisTimer = nil
    }
}
