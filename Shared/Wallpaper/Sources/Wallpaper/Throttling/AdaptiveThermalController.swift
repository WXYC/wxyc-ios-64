import Core
import Foundation

// MARK: - Clock Protocol

/// Protocol for providing the current time, enabling testable time-dependent code.
public protocol ThermalClock: Sendable {
    /// The current time as a TimeInterval since the reference date.
    var now: TimeInterval { get }
}

/// Default clock implementation that uses the system time.
public struct SystemThermalClock: ThermalClock, Sendable {
    public init() {}

    public var now: TimeInterval {
        Date.timeIntervalSinceReferenceDate
    }
}

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

    /// Current shader level of detail (0.0 - 1.0).
    public private(set) var currentLOD: Float = 1.0

    /// Current thermal state from system (for debug display).
    public private(set) var rawThermalState: ProcessInfo.ThermalState = .nominal

    /// Current thermal momentum (for debug display).
    public private(set) var currentMomentum: Float = 0.0

    /// Active shader ID.
    public private(set) var activeShaderID: String?

    // MARK: - Debug Overrides

    /// Debug override for LOD. When set, this value is used instead of adaptive optimization.
    /// Set to nil to return to adaptive behavior.
    public var debugLODOverride: Float? {
        didSet {
            #if DEBUG
            if let lod = debugLODOverride {
                UserDefaults.standard.set(lod, forKey: "wallpaper.debug.lodOverride")
            } else {
                UserDefaults.standard.removeObject(forKey: "wallpaper.debug.lodOverride")
            }
            #endif
        }
    }

    /// Debug override for scale. When set, this value is used instead of adaptive optimization.
    public var debugScaleOverride: Float? {
        didSet {
            #if DEBUG
            if let scale = debugScaleOverride {
                UserDefaults.standard.set(scale, forKey: "wallpaper.debug.scaleOverride")
            } else {
                UserDefaults.standard.removeObject(forKey: "wallpaper.debug.scaleOverride")
            }
            #endif
        }
    }

    /// Debug override for FPS. When set, this value is used instead of adaptive optimization.
    public var debugFPSOverride: Float? {
        didSet {
            #if DEBUG
            if let fps = debugFPSOverride {
                UserDefaults.standard.set(fps, forKey: "wallpaper.debug.fpsOverride")
            } else {
                UserDefaults.standard.removeObject(forKey: "wallpaper.debug.fpsOverride")
            }
            #endif
        }
    }

    /// Effective LOD value, considering debug override.
    public var effectiveLOD: Float {
        debugLODOverride ?? currentLOD
    }

    /// Effective scale value, considering debug override.
    public var effectiveScale: Float {
        debugScaleOverride ?? currentScale
    }

    /// Effective FPS value, considering debug override.
    public var effectiveFPS: Float {
        debugFPSOverride ?? currentFPS
    }

    // MARK: - Dependencies

    private let store: ThermalProfileStore
    private let optimizer: ThermalOptimizer
    private var analytics: ThermalAnalytics?
    private let context: ThermalContextProtocol
    private let clock: ThermalClock

    // MARK: - Internal State

    private var signal = ThermalSignal()
    private var currentProfile: ThermalProfile?
    private var optimizationTask: Task<Void, Never>?
    private var periodicFlushTask: Task<Void, Never>?
    private var contextObservationTask: Task<Void, Never>?
    private var backgroundedAt: TimeInterval?

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
    ///   - clock: Clock for time-based calculations (default: system clock).
    ///   - optimizationInterval: How often to run optimization (default 5 seconds).
    ///   - periodicFlushInterval: How often to flush analytics (default 5 minutes).
    ///   - backgroundThreshold: Time after which to apply cooldown bonus (default 5 minutes).
    public init(
        store: ThermalProfileStore = .shared,
        optimizer: ThermalOptimizer = ThermalOptimizer(),
        analytics: ThermalAnalytics? = nil,
        context: ThermalContextProtocol = ThermalContext.shared,
        clock: ThermalClock = SystemThermalClock(),
        optimizationInterval: Duration = .seconds(5),
        periodicFlushInterval: Duration = .seconds(300),
        backgroundThreshold: TimeInterval = 300
    ) {
        self.store = store
        self.optimizer = optimizer
        self.analytics = analytics
        self.context = context
        self.clock = clock
        self.optimizationInterval = optimizationInterval
        self.periodicFlushInterval = periodicFlushInterval
        self.backgroundThreshold = backgroundThreshold

        // Load persisted debug overrides
        #if DEBUG
        if UserDefaults.standard.object(forKey: "wallpaper.debug.lodOverride") != nil {
            self.debugLODOverride = UserDefaults.standard.float(forKey: "wallpaper.debug.lodOverride")
        }
        if UserDefaults.standard.object(forKey: "wallpaper.debug.scaleOverride") != nil {
            self.debugScaleOverride = UserDefaults.standard.float(forKey: "wallpaper.debug.scaleOverride")
        }
        if UserDefaults.standard.object(forKey: "wallpaper.debug.fpsOverride") != nil {
            self.debugFPSOverride = UserDefaults.standard.float(forKey: "wallpaper.debug.fpsOverride")
        }
        #endif
    }

    /// Configures analytics for session tracking.
    ///
    /// Call this early in app initialization to enable thermal analytics.
    /// - Parameter analytics: The analytics implementation to use.
    public func setAnalytics(_ analytics: ThermalAnalytics) {
        self.analytics = analytics
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
            currentLOD = profile.lod
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
            clock.now - $0 > backgroundThreshold
        } ?? false

        // Reset signal - thermal state during background is unknown
        signal.reset()

        if wasBackgroundedLong, var profile = currentProfile {
            // Apply conservative cooldown bonus
            let fpsBonus = (ThermalProfile.fpsRange.upperBound - profile.fps) * maxCooldownBonus
            let scaleBonus = (ThermalProfile.scaleRange.upperBound - profile.scale) * maxCooldownBonus
            let lodBonus = (ThermalProfile.lodRange.upperBound - profile.lod) * maxCooldownBonus

            profile.update(
                fps: profile.fps + fpsBonus,
                scale: profile.scale + scaleBonus,
                lod: profile.lod + lodBonus
            )
            currentProfile = profile
            currentFPS = profile.fps
            currentScale = profile.scale
            currentLOD = profile.lod
        }

        backgroundedAt = nil
        startOptimizationLoop()
        startPeriodicFlush()
    }

    /// Called when app enters background.
    ///
    /// Pauses optimization and flushes analytics.
    public func handleBackgrounded() {
        backgroundedAt = clock.now
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

    /// Resets the thermal profile for the current shader to default values.
    ///
    /// This removes the persisted profile and resets to max quality (60 FPS, 1.0 scale, 1.0 LOD).
    /// Use this when you want a shader to re-learn its optimal thermal settings.
    public func resetCurrentProfile() {
        guard let shaderID = activeShaderID else { return }

        // Remove persisted profile
        store.remove(shaderId: shaderID)

        // Create fresh default profile
        let freshProfile = ThermalProfile(shaderId: shaderID)
        currentProfile = freshProfile

        // Reset to max quality
        currentFPS = freshProfile.fps
        currentScale = freshProfile.scale
        currentLOD = freshProfile.lod

        // Reset thermal signal
        signal.reset()
        currentMomentum = 0
        fpsMomentumBoost = 0
    }

    /// Reports the measured FPS from the renderer.
    ///
    /// Call this periodically from the render loop when FPS measurements are available.
    /// Reduces LOD/scale/FPS proportionally when below target - this is the primary optimization
    /// mechanism for GPU-bound scenarios.
    ///
    /// - Parameter fps: The measured average FPS.
    public func reportMeasuredFPS(_ fps: Float) {
        let severity = FrameRateMonitor.severity(for: fps)

        // Critical FPS (< 25): immediately drop to minimum LOD and scale
        if severity == .critical {
            forceCriticalThrottle()
            return
        }

        // Proportional FPS-based optimization
        // Reduce all three axes together using optimizer weights
        let targetFPS = currentFPS
        if fps < targetFPS {
            let deficit = (targetFPS - fps) / targetFPS  // 0.0 to 1.0

            // Apply reductions proportionally using optimizer weights (LOD 20%, Scale 60%, FPS 20%)
            // Scale the deficit so moderate drops don't over-throttle
            let adjustedDeficit = deficit * 0.3  // Dampen to avoid oscillation

            // Reduce LOD (20% weight, affects shader complexity)
            let lodReduction = adjustedDeficit * ThermalOptimizer.lodWeight * ThermalOptimizer.maxLODStep * 5
            currentLOD = max(currentLOD - lodReduction, ThermalProfile.lodRange.lowerBound)

            // Reduce scale (60% weight, affects pixel count)
            let scaleReduction = adjustedDeficit * ThermalOptimizer.scaleWeight * ThermalOptimizer.maxScaleStep * 5
            currentScale = max(currentScale - scaleReduction, ThermalProfile.scaleRange.lowerBound)

            // Reduce FPS target (20% weight, last resort)
            let fpsReduction = adjustedDeficit * ThermalOptimizer.fpsWeight * ThermalOptimizer.maxFPSStep * 5
            currentFPS = max(currentFPS - fpsReduction, ThermalProfile.fpsRange.lowerBound)

            // Update profile
            if var profile = currentProfile {
                profile.update(fps: currentFPS, scale: currentScale, lod: currentLOD)
                currentProfile = profile
            }

            // Boost momentum to slow recovery
            fpsMomentumBoost = max(fpsMomentumBoost, deficit)
        }
    }

    /// Forces immediate aggressive throttling due to critical FPS.
    ///
    /// Drops LOD and scale to minimum while keeping FPS target high. Low measured FPS
    /// means the GPU can't keep up with the workload - reducing LOD/scale (less work)
    /// is the fix, not reducing FPS target.
    private func forceCriticalThrottle() {
        // Drop LOD and scale to reduce GPU workload, keep FPS target high
        currentLOD = ThermalProfile.lodRange.lowerBound  // minimum LOD
        currentScale = ThermalProfile.scaleRange.lowerBound  // 0.5 scale
        // Keep currentFPS unchanged - we want smooth animation

        // Update profile so we remember this shader struggles
        if var profile = currentProfile {
            profile.update(fps: currentFPS, scale: currentScale, lod: currentLOD)
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
            currentLOD = ThermalProfile.lodRange.lowerBound
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
        var (newFPS, newScale, newLOD) = optimizer.optimize(current: profile, momentum: effectiveMomentum)

        // Apply gradual quality recovery when thermal is stable
        // This allows the profile to drift back toward max quality over time
        if effectiveMomentum < ThermalSignal.deadZone {
            newFPS = min(newFPS + Self.qualityRecoveryStep * 5, ThermalProfile.fpsRange.upperBound)
            newScale = min(newScale + Self.qualityRecoveryStep, ThermalProfile.scaleRange.upperBound)
            newLOD = min(newLOD + Self.qualityRecoveryStep * 2, ThermalProfile.lodRange.upperBound)
        }

        // Update profile
        profile.update(fps: newFPS, scale: newScale, lod: newLOD)
        profile.thermalMomentum = signal.momentum
        currentProfile = profile

        // Update published values
        currentFPS = newFPS
        currentScale = newScale
        currentLOD = newLOD

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
