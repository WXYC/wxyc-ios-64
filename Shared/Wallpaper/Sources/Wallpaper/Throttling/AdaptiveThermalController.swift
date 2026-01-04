import Foundation

/// Adaptive thermal throttling controller with continuous FPS × Scale optimization.
///
/// Replaces the discrete 4-level `ThermalThrottleController` with continuous
/// optimization. Persists per-shader profiles across app launches and handles
/// app lifecycle transitions properly.
///
/// ## Usage
/// ```swift
/// let controller = AdaptiveThermalController.shared
///
/// // When shader becomes active
/// await controller.setActiveShader("pool_tiles")
///
/// // Read current settings
/// let fps = controller.currentFPS
/// let scale = controller.currentScale
///
/// // App lifecycle
/// controller.handleForegrounded()
/// controller.handleBackgrounded()
/// ```
@Observable
@MainActor
public final class AdaptiveThermalController {

    /// Shared instance using default dependencies.
    public static let shared = AdaptiveThermalController()

    // MARK: - Published State

    /// Current target FPS (15.0 - 60.0).
    public private(set) var currentFPS: Float = 60.0

    /// Current render scale (0.5 - 1.0).
    public private(set) var currentScale: Float = 1.0

    /// Current thermal state from system (for debug display).
    public private(set) var rawThermalState: ProcessInfo.ThermalState = .nominal

    /// Current thermal momentum (for debug display).
    public private(set) var currentMomentum: Float = 0.0

    /// Active shader ID.
    public private(set) var activeShaderID: String?

    // MARK: - Dependencies

    private let store: ThermalProfileStore
    private let optimizer: ThermalOptimizer
    private let analytics: ThermalAnalytics?
    private let thermalStateProvider: @Sendable () -> ProcessInfo.ThermalState

    // MARK: - Internal State

    private var signal = ThermalSignal()
    private var currentProfile: ThermalProfile?
    private var optimizationTask: Task<Void, Never>?
    private var periodicFlushTask: Task<Void, Never>?
    private var backgroundedAt: Date?

    /// Optimization loop interval.
    private let optimizationInterval: Duration

    /// Periodic analytics flush interval.
    private let periodicFlushInterval: Duration

    /// Background duration threshold for conservative restart.
    private let backgroundThreshold: TimeInterval

    /// Maximum quality boost when returning from long background.
    private let maxCooldownBonus: Float = 0.2

    // MARK: - Initialization

    /// Creates an adaptive thermal controller with injectable dependencies.
    ///
    /// - Parameters:
    ///   - store: Profile persistence store.
    ///   - optimizer: Optimization algorithm.
    ///   - analytics: Analytics for session tracking (optional).
    ///   - thermalStateProvider: Closure returning current thermal state.
    ///   - optimizationInterval: How often to run optimization (default 5 seconds).
    ///   - periodicFlushInterval: How often to flush analytics (default 5 minutes).
    ///   - backgroundThreshold: Time after which to apply cooldown bonus (default 5 minutes).
    public init(
        store: ThermalProfileStore = .shared,
        optimizer: ThermalOptimizer = ThermalOptimizer(),
        analytics: ThermalAnalytics? = nil,
        thermalStateProvider: @escaping @Sendable () -> ProcessInfo.ThermalState = { ProcessInfo.processInfo.thermalState },
        optimizationInterval: Duration = .seconds(5),
        periodicFlushInterval: Duration = .seconds(300),
        backgroundThreshold: TimeInterval = 300
    ) {
        self.store = store
        self.optimizer = optimizer
        self.analytics = analytics
        self.thermalStateProvider = thermalStateProvider
        self.optimizationInterval = optimizationInterval
        self.periodicFlushInterval = periodicFlushInterval
        self.backgroundThreshold = backgroundThreshold
    }

    // MARK: - Public API

    /// Sets the active shader and loads its thermal profile.
    ///
    /// Call this when the wallpaper view appears with a specific shader.
    ///
    /// - Parameter shaderID: The shader identifier.
    public func setActiveShader(_ shaderID: String) async {
        // Flush previous shader session if any
        if activeShaderID != nil && activeShaderID != shaderID {
            analytics?.flush(reason: .shaderChanged)
        }

        activeShaderID = shaderID
        currentProfile = store.load(shaderId: shaderID)

        if let profile = currentProfile {
            currentFPS = profile.fps
            currentScale = profile.scale
        }

        startOptimizationLoop()
        startPeriodicFlush()
    }

    /// Called when app returns to foreground.
    ///
    /// Resets thermal signal (unknown state during background) and applies
    /// conservative cooldown bonus if backgrounded long enough.
    public func handleForegrounded() {
        let wasBackgroundedLong = backgroundedAt.map {
            Date().timeIntervalSince($0) > backgroundThreshold
        } ?? false

        // Reset signal - thermal state during background is unknown
        signal.reset()

        if wasBackgroundedLong, var profile = currentProfile {
            // Apply conservative cooldown bonus
            let fpsBonus = (ThermalProfile.fpsRange.upperBound - profile.fps) * maxCooldownBonus
            let scaleBonus = (ThermalProfile.scaleRange.upperBound - profile.scale) * maxCooldownBonus

            profile.update(fps: profile.fps + fpsBonus, scale: profile.scale + scaleBonus)
            currentProfile = profile
            currentFPS = profile.fps
            currentScale = profile.scale
        }

        backgroundedAt = nil
        startOptimizationLoop()
        startPeriodicFlush()
    }

    /// Called when app enters background.
    ///
    /// Pauses optimization and flushes analytics.
    public func handleBackgrounded() {
        backgroundedAt = Date()
        stopOptimizationLoop()
        stopPeriodicFlush()

        // Flush analytics
        analytics?.flush(reason: .background)

        // Persist current profile
        if let profile = currentProfile {
            store.save(profile)
        }
    }

    /// Manually triggers an optimization check.
    ///
    /// Useful for testing or forcing an immediate update.
    public func checkNow() {
        performOptimizationTick()
    }

    // MARK: - Optimization Loop

    private func startOptimizationLoop() {
        stopOptimizationLoop()

        optimizationTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                self.performOptimizationTick()

                do {
                    try await Task.sleep(for: self.optimizationInterval)
                } catch {
                    break
                }
            }
        }
    }

    private func stopOptimizationLoop() {
        optimizationTask?.cancel()
        optimizationTask = nil
    }

    private func performOptimizationTick() {
        // Update thermal state
        let state = thermalStateProvider()
        rawThermalState = state
        signal.record(state)
        currentMomentum = signal.momentum

        guard var profile = currentProfile else { return }

        // Optimize
        let (newFPS, newScale) = optimizer.optimize(current: profile, momentum: signal.momentum)

        // Update profile
        profile.update(fps: newFPS, scale: newScale)
        profile.thermalMomentum = signal.momentum
        currentProfile = profile

        // Update published values
        currentFPS = newFPS
        currentScale = newScale

        // Record analytics event
        if let shaderID = activeShaderID {
            let event = ThermalAdjustmentEvent(
                shaderId: shaderID,
                fps: newFPS,
                scale: newScale,
                thermalState: state,
                momentum: signal.momentum
            )
            analytics?.record(event)
        }

        // Persist periodically (every 12 ticks = ~1 minute)
        if profile.sampleCount % 12 == 0 {
            store.save(profile)
        }
    }

    // MARK: - Periodic Flush

    private func startPeriodicFlush() {
        stopPeriodicFlush()

        periodicFlushTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: self.periodicFlushInterval)
                    self.analytics?.flush(reason: .periodic)
                } catch {
                    break
                }
            }
        }
    }

    private func stopPeriodicFlush() {
        periodicFlushTask?.cancel()
        periodicFlushTask = nil
    }
}

// MARK: - Convenience Factory

extension AdaptiveThermalController {

    /// Creates a controller with PostHog analytics enabled.
    public static func withPostHogAnalytics() -> AdaptiveThermalController {
        let reporter = PostHogThermalReporter()
        let aggregator = ThermalMetricsAggregator(reporter: reporter)
        return AdaptiveThermalController(analytics: aggregator)
    }
}
