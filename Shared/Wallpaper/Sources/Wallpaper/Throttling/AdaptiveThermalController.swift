import Core
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
    private let context: ThermalContextProtocol

    // MARK: - Internal State

    private var signal = ThermalSignal()
    private var currentProfile: ThermalProfile?
    private var optimizationTask: Task<Void, Never>?
    private var periodicFlushTask: Task<Void, Never>?
    private var contextObservationTask: Task<Void, Never>?
    private var backgroundedAt: Date?

    /// FPS-based momentum boost (decays over time).
    private var fpsMomentumBoost: Float = 0

    /// Quality recovery step per optimization tick.
    private static let qualityRecoveryStep: Float = 0.01

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
    ///   - context: Thermal context for system state observation.
    ///   - optimizationInterval: How often to run optimization (default 5 seconds).
    ///   - periodicFlushInterval: How often to flush analytics (default 5 minutes).
    ///   - backgroundThreshold: Time after which to apply cooldown bonus (default 5 minutes).
    public init(
        store: ThermalProfileStore = .shared,
        optimizer: ThermalOptimizer = ThermalOptimizer(),
        analytics: ThermalAnalytics? = nil,
        context: ThermalContextProtocol = ThermalContext.shared,
        optimizationInterval: Duration = .seconds(5),
        periodicFlushInterval: Duration = .seconds(300),
        backgroundThreshold: TimeInterval = 300
    ) {
        self.store = store
        self.optimizer = optimizer
        self.analytics = analytics
        self.context = context
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

    /// Reports the measured FPS from the renderer.
    ///
    /// Call this periodically from the render loop when FPS measurements are available.
    /// Critically low FPS (< 25) triggers immediate aggressive throttling to floor values.
    /// Low FPS (< 50) boosts momentum for faster quality reduction.
    ///
    /// - Parameter fps: The measured average FPS.
    public func reportMeasuredFPS(_ fps: Float) {
        let severity = FrameRateMonitor.severity(for: fps)

        // Critical FPS: immediately force floor values
        // The GPU is severely overloaded - gradual reduction won't help
        if severity == .critical {
            forceCriticalThrottle()
            return
        }

        // Warning level: boost momentum for faster reduction
        fpsMomentumBoost = severity.momentumBoost
    }

    /// Forces immediate aggressive throttling due to critical FPS.
    ///
    /// Drops scale to minimum while keeping FPS target high. Low measured FPS
    /// means the GPU can't keep up with the workload - reducing scale (fewer pixels)
    /// is the fix, not reducing FPS target.
    private func forceCriticalThrottle() {
        // Drop scale to reduce GPU workload, keep FPS target high
        currentScale = ThermalProfile.scaleRange.lowerBound  // 0.5 scale
        // Keep currentFPS unchanged - we want smooth animation

        // Update profile so we remember this shader struggles
        if var profile = currentProfile {
            profile.update(fps: currentFPS, scale: currentScale)
            currentProfile = profile

            // Persist immediately - this shader needs aggressive settings
            if !context.hasExternalFactors {
                store.save(profile)
            }
        }

        // Set high momentum so recovery is slow
        currentMomentum = 1.0
        fpsMomentumBoost = 0
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
        // Low power mode: force aggressive throttle to save battery
        if context.isLowPowerMode {
            currentFPS = ThermalContext.lowPowerFPS
            currentScale = ThermalContext.lowPowerScale
            rawThermalState = context.thermalState
            currentMomentum = 0
            // Don't update profile or persist - this is temporary
            return
        }

        // Update thermal state from context
        let state = context.thermalState
        rawThermalState = state
        signal.record(state)

        // Combine thermal momentum with FPS-based boost
        let effectiveMomentum = min(signal.momentum + fpsMomentumBoost, 1.0)
        currentMomentum = effectiveMomentum

        // Decay FPS boost over time (so it doesn't persist indefinitely)
        fpsMomentumBoost *= 0.8

        guard var profile = currentProfile else { return }

        // Optimize using effective momentum
        var (newFPS, newScale) = optimizer.optimize(current: profile, momentum: effectiveMomentum)

        // Apply gradual quality recovery when thermal is stable
        // This allows the profile to drift back toward max quality over time
        if effectiveMomentum < ThermalSignal.deadZone {
            newFPS = min(newFPS + Self.qualityRecoveryStep * 5, ThermalProfile.fpsRange.upperBound)
            newScale = min(newScale + Self.qualityRecoveryStep, ThermalProfile.scaleRange.upperBound)
        }

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
        // But not when charging - external heat source may skew profile
        if !context.hasExternalFactors && profile.sampleCount % 12 == 0 {
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
