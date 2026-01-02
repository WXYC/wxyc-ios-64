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
    private var _currentLevel: ThermalThrottleLevel = .nominal {
        didSet {
            if oldValue != _currentLevel {
                levelContinuation?.yield(_currentLevel)
            }
        }
    }

    /// Debug override for throttle level. Set to nil to use automatic thermal-based throttling.
    public var debugOverrideLevel: ThermalThrottleLevel? {
        didSet {
            if oldValue != debugOverrideLevel {
                levelContinuation?.yield(currentLevel)
            }
        }
    }

    /// Raw thermal state from system (for debug display).
    public private(set) var rawThermalState: ProcessInfo.ThermalState = .nominal

    /// Provider for thermal state (injectable for testing).
    private let thermalStateProvider: @Sendable () -> ProcessInfo.ThermalState

    /// Hysteresis delay before ramping quality back up.
    private let hysteresisDelay: Duration

    /// Polling interval for thermal state checks.
    private let pollingInterval: Duration

    /// Time when thermal state last improved (for hysteresis).
    private var lastImprovementTime: ContinuousClock.Instant?

    /// Task for periodic thermal monitoring.
    private var monitoringTask: Task<Void, Never>?

    /// Task for hysteresis recovery.
    private var hysteresisTask: Task<Void, Never>?

    /// Continuation for the level changes stream.
    private var levelContinuation: AsyncStream<ThermalThrottleLevel>.Continuation?

    /// AsyncStream of throttle level changes.
    @ObservationIgnored
    public private(set) lazy var levelChanges: AsyncStream<ThermalThrottleLevel> = {
        AsyncStream { continuation in
            self.levelContinuation = continuation
            // Yield current level immediately
            continuation.yield(self.currentLevel)

            continuation.onTermination = { @Sendable _ in
                Task { @MainActor in
                    self.levelContinuation = nil
                }
            }
        }
    }()

    /// Creates a controller with injectable dependencies for testing.
    ///
    /// - Parameters:
    ///   - thermalStateProvider: Closure returning current thermal state.
    ///   - hysteresisDelay: Duration to wait before upgrading quality after cooling.
    ///   - pollingInterval: Duration between thermal state checks.
    ///   - startMonitoringAutomatically: Whether to start polling immediately.
    public init(
        thermalStateProvider: @escaping @Sendable () -> ProcessInfo.ThermalState = { ProcessInfo.processInfo.thermalState },
        hysteresisDelay: Duration = .seconds(30),
        pollingInterval: Duration = .seconds(5),
        startMonitoringAutomatically: Bool = true
    ) {
        self.thermalStateProvider = thermalStateProvider
        self.hysteresisDelay = hysteresisDelay
        self.pollingInterval = pollingInterval

        // Initialize with current state
        updateThermalState()

        if startMonitoringAutomatically {
            startMonitoring()
        }
    }

    /// Starts periodic thermal monitoring.
    public func startMonitoring() {
        stopMonitoring()

        monitoringTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                self.checkThermalState()

                do {
                    try await Task.sleep(for: self.pollingInterval)
                } catch {
                    break
                }
            }
        }
    }

    /// Stops periodic thermal monitoring.
    public func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
        hysteresisTask?.cancel()
        hysteresisTask = nil
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

        let elapsed = ContinuousClock.now - improvementTime
        if elapsed >= hysteresisDelay {
            let targetLevel = ThermalThrottleLevel(thermalState: rawThermalState)
            if targetLevel.isBetterThan(_currentLevel) {
                // Step up one level
                _currentLevel = _currentLevel.nextBetterLevel

                // If still not at target, schedule another check
                if _currentLevel != targetLevel {
                    lastImprovementTime = .now
                    scheduleHysteresisCheck()
                } else {
                    lastImprovementTime = nil
                    cancelHysteresisTask()
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
            cancelHysteresisTask()
        } else if newLevel.isBetterThan(_currentLevel) {
            // Start or continue hysteresis timer
            if lastImprovementTime == nil {
                lastImprovementTime = .now
                scheduleHysteresisCheck()
            }
        }
        // If equal, no action needed
    }

    private func scheduleHysteresisCheck() {
        cancelHysteresisTask()

        hysteresisTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(for: self.hysteresisDelay)
                self.checkHysteresisRecovery()
            } catch {
                // Task was cancelled
            }
        }
    }

    private func cancelHysteresisTask() {
        hysteresisTask?.cancel()
        hysteresisTask = nil
    }
}
