import Core
import Foundation

// MARK: - Clock Protocol

/// Protocol for providing the current time, enabling testable time-dependent code.
public protocol QualityClock: Sendable {
    /// The current time as a TimeInterval since the reference date.
    var now: TimeInterval { get }
}

/// Default clock implementation that uses the system time.
public struct SystemQualityClock: QualityClock, Sendable {
    public init() {}

    public var now: TimeInterval {
        Date.timeIntervalSinceReferenceDate
    }
}

// MARK: - Throttling Mode

/// Throttling algorithm mode.
///
/// Controls how aggressively the thermal controller responds to thermal pressure.
public enum ThrottlingMode: String, Sendable, CaseIterable {
    /// Normal throttling mode.
    ///
    /// Balanced response to thermal pressure with gradual quality recovery.
    /// Suitable for most usage scenarios.
    case normal

    /// Low power throttling mode.
    ///
    /// More aggressive throttling that responds faster to thermal pressure
    /// and recovers quality more slowly. Useful for extending battery life
    /// or when the device is already warm.
    case lowPower

    /// Momentum multiplier applied to thermal signals.
    ///
    /// Higher values cause faster throttling response.
    var momentumMultiplier: Float {
        switch self {
        case .normal: 1.0
        case .lowPower: 1.5
        }
    }

    /// Quality recovery step multiplier.
    ///
    /// Lower values cause slower quality recovery when thermal is stable.
    var recoveryMultiplier: Float {
        switch self {
        case .normal: 1.0
        case .lowPower: 0.5
        }
    }

    /// Scale threshold for enabling interpolation.
    ///
    /// Lower values enable interpolation earlier (more aggressive power saving).
    var interpolationScaleThreshold: Float {
        switch self {
        case .normal: 0.85
        case .lowPower: 0.95
        }
    }

    /// Momentum dead zone threshold.
    ///
    /// Lower values require more stability before quality recovery begins.
    var deadZoneThreshold: Float {
        switch self {
        case .normal: QualitySignal.deadZone
        case .lowPower: QualitySignal.deadZone * 0.5
        }
    }
}

/// Adaptive thermal throttling controller with continuous wallpaper FPS × Scale optimization.
///
/// Replaces the discrete 4-level `ThermalThrottleController` with continuous
/// optimization. Persists per-shader profiles across app launches and handles
/// app lifecycle transitions properly.
///
/// ## Usage
/// ```swift
/// let controller = AdaptiveQualityController.shared
///
/// // When shader becomes active
/// await controller.setActiveShader("pool_tiles")
///
/// // Read current settings
/// let wallpaperFPS = controller.currentWallpaperFPS
/// let scale = controller.currentScale
///
/// // App lifecycle
/// controller.handleForegrounded()
/// controller.handleBackgrounded()
/// ```
@Observable
@MainActor
public final class AdaptiveQualityController {

    /// Shared instance using default dependencies.
    public static let shared = AdaptiveQualityController()

    // MARK: - Published State

    /// Current target wallpaper FPS (15.0 - 60.0).
    public private(set) var currentWallpaperFPS: Float = 60.0

    /// Current render scale (0.5 - 1.0).
    public private(set) var currentScale: Float = 1.0

    /// Current shader level of detail (0.0 - 1.0).
    public private(set) var currentLOD: Float = 1.0

    /// Whether frame interpolation is currently enabled.
    ///
    /// When true, the renderer should execute the shader at `shaderFPS` while
    /// displaying at `currentWallpaperFPS` by blending between cached frames.
    public private(set) var interpolationEnabled: Bool = false

    /// The FPS at which the shader executes when interpolation is enabled.
    ///
    /// When `interpolationEnabled` is false, this equals `currentWallpaperFPS`.
    public private(set) var shaderFPS: Float = 60.0

    /// Current thermal state from system (for debug display).
    public private(set) var rawThermalState: ProcessInfo.ThermalState = .nominal

    /// Current thermal momentum (for debug display).
    public private(set) var currentMomentum: Float = 0.0

    /// Active shader ID.
    public private(set) var activeShaderID: String?

    /// Whether the device is in Low Power Mode.
    ///
    /// When true, throttling values are forced to aggressive settings regardless
    /// of thermal state or learned profile.
    public var isLowPowerMode: Bool {
        context.isLowPowerMode
    }

    /// Counter incremented each time the profile is reset.
    /// Renderers can observe this to reset their frame rate monitors.
    public private(set) var profileResetCount: Int = 0

    /// Current throttling mode.
    ///
    /// Controls how aggressively the controller responds to thermal pressure.
    /// Can be changed at runtime.
    public var mode: ThrottlingMode = .normal

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

    /// Debug override for wallpaper FPS. When set, this value is used instead of adaptive optimization.
    public var debugWallpaperFPSOverride: Float? {
        didSet {
            #if DEBUG
            if let fps = debugWallpaperFPSOverride {
                UserDefaults.standard.set(fps, forKey: "wallpaper.debug.wallpaperFPSOverride")
            } else {
                UserDefaults.standard.removeObject(forKey: "wallpaper.debug.wallpaperFPSOverride")
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

    /// Effective wallpaper FPS value, considering debug override.
    public var effectiveWallpaperFPS: Float {
        debugWallpaperFPSOverride ?? currentWallpaperFPS
    }

    /// Effective interpolation enabled state.
    ///
    /// Currently no debug override for interpolation, but could be added.
    public var effectiveInterpolationEnabled: Bool {
        interpolationEnabled
    }

    /// Effective shader FPS value.
    ///
    /// When interpolation is disabled, this equals `effectiveWallpaperFPS`.
    public var effectiveShaderFPS: Float {
        interpolationEnabled ? shaderFPS : effectiveWallpaperFPS
    }

    // MARK: - Dependencies

    private let store: AdaptiveProfileStore
    private let optimizer: QualityOptimizer
    private var analytics: QualityAnalytics?
    private let context: DeviceContextProtocol
    private let clock: QualityClock

    // MARK: - Internal State

    private var signal = QualitySignal()
    private var currentProfile: AdaptiveProfile?
    private var optimizationTask: Task<Void, Never>?
    private var periodicFlushTask: Task<Void, Never>?
    private var contextObservationTask: Task<Void, Never>?
    private var backgroundedAt: TimeInterval?

    /// FPS-based momentum boost (decays over time).
    /// Applied when measured FPS is significantly below target.
    private var fpsMomentumBoost: Float = 0

    /// Timestamp of last profile reset (for grace period).
    private var lastProfileResetTime: TimeInterval?

    /// Grace period duration after profile reset during which critical throttle is disabled.
    /// This allows gradual throttling instead of snap-to-minimum while the system learns.
    private static let gracePeriodDuration: TimeInterval = 10.0

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
    ///   - mode: Throttling mode controlling response aggressiveness (default: normal).
    ///   - optimizationInterval: How often to run optimization (default 5 seconds).
    ///   - periodicFlushInterval: How often to flush analytics (default 5 minutes).
    ///   - backgroundThreshold: Time after which to apply cooldown bonus (default 5 minutes).
    public init(
        store: AdaptiveProfileStore = .shared,
        optimizer: QualityOptimizer = QualityOptimizer(),
        analytics: QualityAnalytics? = nil,
        context: DeviceContextProtocol = DeviceContext.shared,
        clock: QualityClock = SystemQualityClock(),
        mode: ThrottlingMode = .normal,
        optimizationInterval: Duration = .seconds(5),
        periodicFlushInterval: Duration = .seconds(300),
        backgroundThreshold: TimeInterval = 300
    ) {
        self.store = store
        self.optimizer = optimizer
        self.analytics = analytics
        self.context = context
        self.clock = clock
        self.mode = mode
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
        if UserDefaults.standard.object(forKey: "wallpaper.debug.wallpaperFPSOverride") != nil {
            self.debugWallpaperFPSOverride = UserDefaults.standard.float(forKey: "wallpaper.debug.wallpaperFPSOverride")
        }
        #endif
    }

    /// Configures analytics for session tracking.
    ///
    /// Call this early in app initialization to enable thermal analytics.
    /// - Parameter analytics: The analytics implementation to use.
    public func setAnalytics(_ analytics: QualityAnalytics) {
        self.analytics = analytics
    }

    // MARK: - Public API

    /// Sets the active shader and loads its thermal profile.
    ///
    /// Call this when the wallpaper view appears with a specific shader.
    /// If the device is not at nominal temperature, the loaded profile's quality
    /// values are adjusted to prevent quality spikes when switching wallpapers.
    ///
    /// - Parameter shaderID: The shader identifier.
    public func setActiveShader(_ shaderID: String) async {
        // Flush previous shader session if any
        if activeShaderID != nil && activeShaderID != shaderID {
            analytics?.flush(reason: .shaderChanged)
        }

        activeShaderID = shaderID
        var profile = store.load(shaderId: shaderID)

        // Apply current thermal state to loaded profile
        // This prevents quality spikes when switching while device is hot
        // Use the thermal state's normalized value as minimum momentum, since
        // momentum represents change (delta) not absolute state
        let thermalState = context.thermalState
        if thermalState != .nominal {
            let stateBasedMomentum = thermalState.normalizedValue
            let effectiveMomentum = max(signal.momentum, stateBasedMomentum)
            let (newFPS, newScale, newLOD) = optimizer.optimize(
                current: profile,
                momentum: effectiveMomentum
            )
            // Take the more conservative of stored vs thermally-adjusted values
            profile.update(
                wallpaperFPS: min(profile.wallpaperFPS, newFPS),
                scale: min(profile.scale, newScale),
                lod: min(profile.lod, newLOD)
            )
        }

        currentProfile = profile
        currentWallpaperFPS = profile.wallpaperFPS
        currentScale = profile.scale
        currentLOD = profile.lod

        startOptimizationLoop()
        startPeriodicFlush()
    }

    /// Called when app returns to foreground.
    ///
    /// Seeds thermal signal from current device state and applies
    /// conservative cooldown bonus if backgrounded long enough.
    public func handleForegrounded() {
        let wasBackgroundedLong = backgroundedAt.map {
            clock.now - $0 > backgroundThreshold
        } ?? false

        // Seed signal from current thermal state - device may be hot
        // This ensures we respond immediately rather than waiting for first optimization tick
        let currentState = context.thermalState
        signal.seedFromCurrentState(currentState)
        rawThermalState = currentState
        currentMomentum = signal.momentum

        if wasBackgroundedLong, var profile = currentProfile {
            // Apply conservative cooldown bonus
            let fpsBonus = (AdaptiveProfile.wallpaperFPSRange.upperBound - profile.wallpaperFPS) * maxCooldownBonus
            let scaleBonus = (AdaptiveProfile.scaleRange.upperBound - profile.scale) * maxCooldownBonus
            let lodBonus = (AdaptiveProfile.lodRange.upperBound - profile.lod) * maxCooldownBonus

            profile.update(
                wallpaperFPS: profile.wallpaperFPS + fpsBonus,
                scale: profile.scale + scaleBonus,
                lod: profile.lod + lodBonus
            )
            currentProfile = profile
            currentWallpaperFPS = profile.wallpaperFPS
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
    ///
    /// A grace period is applied after reset during which critical throttle is disabled,
    /// allowing gradual throttling instead of snap-to-minimum behavior.
    public func resetCurrentProfile() {
        guard let shaderID = activeShaderID else { return }

        // Remove persisted profile
        store.remove(shaderId: shaderID)

        // Create fresh default profile
        let freshProfile = AdaptiveProfile(shaderId: shaderID)
        currentProfile = freshProfile

        // Reset to max quality
        currentWallpaperFPS = freshProfile.wallpaperFPS
        currentScale = freshProfile.scale
        currentLOD = freshProfile.lod

        // Reset thermal signal
        signal.reset()
        currentMomentum = 0
        fpsMomentumBoost = 0

        // Start grace period for gradual learning
        lastProfileResetTime = clock.now

        // Notify observers (renderers) to reset their frame rate monitors
        profileResetCount += 1
    }

    // MARK: - FPS-Based Throttling

    /// Tolerance for FPS measurements before triggering throttling.
    /// FPS within this range of target is considered "on target" (accounts for vsync variance).
    private static let fpsTolerance: Float = 3.0

    /// Reports the measured FPS from the renderer.
    ///
    /// Boosts momentum when FPS is significantly below target, causing the optimizer
    /// to reduce quality. This provides reactive throttling when the GPU can't keep up,
    /// complementing the proactive thermal-based throttling.
    ///
    /// - Parameter fps: The measured average FPS.
    public func reportMeasuredFPS(_ fps: Float) {
        let targetFPS = currentWallpaperFPS
        let deficit = targetFPS - fps

        // Only apply FPS boost if deficit exceeds tolerance (ignore vsync variance)
        guard deficit > Self.fpsTolerance else { return }

        let normalizedDeficit = min((deficit - Self.fpsTolerance) / targetFPS, 1.0)
        // FPS boost is secondary to thermal - use a gentler multiplier
        fpsMomentumBoost = max(fpsMomentumBoost, normalizedDeficit * 0.5)
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
            currentWallpaperFPS = DeviceContext.lowPowerWallpaperFPS
            currentScale = DeviceContext.lowPowerScale
            currentLOD = AdaptiveProfile.lodRange.lowerBound
            rawThermalState = context.thermalState
            currentMomentum = 0
            // Enable interpolation in low power mode for additional savings
            interpolationEnabled = true
            shaderFPS = DeviceContext.lowPowerWallpaperFPS / 2
            // Don't update profile or persist - this is temporary
            return
        }

        // Update thermal state from context
        let state = context.thermalState
        rawThermalState = state
        signal.record(state)

        // Combine thermal momentum with FPS-based boost, scaled by mode
        let baseMomentum = signal.momentum * mode.momentumMultiplier
        let effectiveMomentum = min(baseMomentum + fpsMomentumBoost, 1.0)
        // Decay FPS boost over time (so it doesn't persist indefinitely)
        fpsMomentumBoost *= 0.8
        currentMomentum = effectiveMomentum

        guard var profile = currentProfile else { return }

        // Optimize using effective momentum (3-axis: LOD, Scale, FPS)
        var (newWallpaperFPS, newScale, newLOD) = optimizer.optimize(
            current: profile,
            momentum: effectiveMomentum
        )

        // Apply gradual quality recovery when thermal is stable
        // This allows the profile to drift back toward max quality over time
        // Mode controls how quickly recovery happens (low power mode recovers more slowly)
        if effectiveMomentum < mode.deadZoneThreshold {
            let recoveryStep = Self.qualityRecoveryStep * mode.recoveryMultiplier
            newWallpaperFPS = min(newWallpaperFPS + recoveryStep * 5, AdaptiveProfile.wallpaperFPSRange.upperBound)
            newScale = min(newScale + recoveryStep, AdaptiveProfile.scaleRange.upperBound)
            newLOD = min(newLOD + recoveryStep * 2, AdaptiveProfile.lodRange.upperBound)
        }

        // Update profile
        profile.update(wallpaperFPS: newWallpaperFPS, scale: newScale, lod: newLOD)
        profile.qualityMomentum = effectiveMomentum
        currentProfile = profile

        // Update published values
        currentWallpaperFPS = newWallpaperFPS
        currentScale = newScale
        currentLOD = newLOD

        // Update interpolation state based on current throttling tier
        updateInterpolationState(scale: newScale, displayFPS: newWallpaperFPS, momentum: effectiveMomentum)

        // Record analytics event
        if let shaderID = activeShaderID {
            let event = QualityAdjustmentEvent(
                shaderId: shaderID,
                wallpaperFPS: newWallpaperFPS,
                scale: newScale,
                lod: newLOD,
                thermalState: state,
                momentum: effectiveMomentum,
                interpolationEnabled: interpolationEnabled,
                shaderFPS: shaderFPS
            )
            analytics?.record(event)
        }

        // Persist periodically (every 12 ticks = ~1 minute)
        // But not when charging - external heat source may skew profile
        if !context.hasExternalFactors && profile.sampleCount % 12 == 0 {
            store.save(profile)
        }
    }

    // MARK: - Interpolation State

    /// Updates the interpolation state based on current throttling parameters.
    ///
    /// Interpolation is enabled as a middle tier when:
    /// - Scale has been reduced below a threshold (thermal pressure exists)
    /// - Display FPS is still at or near 60 (we haven't fallen back to FPS reduction yet)
    ///
    /// This allows us to maintain smooth 60fps display while only executing the shader
    /// at a lower rate (e.g., 30fps), reducing GPU workload by ~50%.
    ///
    /// The scale threshold is mode-dependent: low power mode enables interpolation earlier.
    private func updateInterpolationState(scale: Float, displayFPS: Float, momentum: Float) {
        // Thresholds for interpolation activation (mode-dependent)
        let scaleThreshold = mode.interpolationScaleThreshold
        let fpsThreshold: Float = 50.0  // Only interpolate when display FPS is still high

        // Enable interpolation when we've started throttling scale but FPS is still high
        // This is the "middle tier" of throttling
        let shouldInterpolate = scale < scaleThreshold && displayFPS >= fpsThreshold

        if shouldInterpolate {
            interpolationEnabled = true
            // Shader executes at half the display rate when interpolating
            // This gives us 50% reduction in shader work while maintaining smooth display
            shaderFPS = displayFPS / 2
        } else {
            interpolationEnabled = false
            shaderFPS = displayFPS
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
