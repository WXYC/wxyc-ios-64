import Foundation
import Testing
@testable import Wallpaper

// MARK: - Mock Clock

/// Mock clock for testing time-dependent behavior.
@MainActor
final class MockThermalClock: ThermalClock, @unchecked Sendable {
    private var _now: TimeInterval = 0

    nonisolated var now: TimeInterval {
        MainActor.assumeIsolated { _now }
    }

    func advance(by seconds: TimeInterval) {
        _now += seconds
    }

    func set(_ time: TimeInterval) {
        _now = time
    }
}

@Suite("AdaptiveThermalController")
@MainActor
struct AdaptiveThermalControllerTests {

    /// Creates a test controller with injectable context and clock.
    func makeController(
        context: ThermalContextProtocol = MockThermalContext(),
        analytics: ThermalAnalytics? = nil,
        clock: ThermalClock = SystemThermalClock()
    ) -> AdaptiveThermalController {
        let defaults = UserDefaults(suiteName: "AdaptiveThermalControllerTests-\(UUID().uuidString)")!
        let store = ThermalProfileStore(defaults: defaults)

        return AdaptiveThermalController(
            store: store,
            optimizer: ThermalOptimizer(),
            analytics: analytics,
            context: context,
            clock: clock,
            optimizationInterval: .milliseconds(10),
            periodicFlushInterval: .seconds(300),
            backgroundThreshold: 1  // 1 second for testing
        )
    }

    @Test("Initial state is max quality")
    func initialState() {
        let controller = makeController()

        #expect(controller.currentWallpaperFPS == 60.0)
        #expect(controller.currentScale == 1.0)
        #expect(controller.currentLOD == 1.0)
        #expect(controller.activeShaderID == nil)
    }

    @Test("setActiveShader loads profile")
    func setActiveShaderLoadsProfile() async {
        let controller = makeController()

        await controller.setActiveShader("test_shader")

        #expect(controller.activeShaderID == "test_shader")
        #expect(controller.currentWallpaperFPS == 60.0)
        #expect(controller.currentScale == 1.0)
        #expect(controller.currentLOD == 1.0)
    }

    @Test("Heating reduces quality")
    func heatingReducesQuality() async throws {
        let context = MockThermalContext(thermalState: .nominal)
        let controller = makeController(context: context)

        await controller.setActiveShader("test")

        // Record initial state so signal has a baseline
        controller.checkNow()

        // Simulate heating progression (each tick increases thermal state)
        // This generates positive delta each time, building momentum
        context.thermalState = .fair
        controller.checkNow()
        context.thermalState = .serious
        controller.checkNow()
        context.thermalState = .critical
        controller.checkNow()
        controller.checkNow()

        #expect(controller.currentWallpaperFPS < 60.0)
        #expect(controller.currentScale < 1.0)
        #expect(controller.currentLOD < 1.0)
    }

    @Test("Background flushes analytics")
    func backgroundFlushesAnalytics() async {
        let analytics = MockThermalAnalytics()
        let controller = makeController(analytics: analytics)

        await controller.setActiveShader("test")
        controller.checkNow()

        controller.handleBackgrounded()

        #expect(analytics.flushReasons.contains(.background))
    }

    @Test("Shader change flushes previous session")
    func shaderChangeFlushes() async {
        let analytics = MockThermalAnalytics()
        let controller = makeController(analytics: analytics)

        await controller.setActiveShader("shader1")
        controller.checkNow()

        await controller.setActiveShader("shader2")

        #expect(analytics.flushReasons.contains(.shaderChanged))
    }

    @Test("Foreground after long background applies cooldown bonus")
    func foregroundAppliesCooldownBonus() async {
        let context = MockThermalContext(thermalState: .critical)
        let mockClock = MockThermalClock()
        let controller = makeController(context: context, clock: mockClock)

        await controller.setActiveShader("test")

        // Heat up
        controller.checkNow()
        controller.checkNow()
        controller.checkNow()

        let throttledFPS = controller.currentWallpaperFPS
        let throttledScale = controller.currentScale
        let throttledLOD = controller.currentLOD

        // Background
        controller.handleBackgrounded()

        // Advance time past the background threshold (> 1 second in our test config)
        mockClock.advance(by: 1.5)

        // Cool down while backgrounded
        context.thermalState = .nominal

        // Foreground
        controller.handleForegrounded()

        // Should have some recovery bonus
        #expect(controller.currentWallpaperFPS >= throttledFPS)
        #expect(controller.currentScale >= throttledScale)
        #expect(controller.currentLOD >= throttledLOD)
    }

    @Test("checkNow updates thermal state")
    func checkNowUpdatesThermalState() async {
        let context = MockThermalContext(thermalState: .nominal)
        let controller = makeController(context: context)

        await controller.setActiveShader("test")

        context.thermalState = .serious
        controller.checkNow()

        #expect(controller.rawThermalState == .serious)
    }

    @Test("Analytics receives adjustment events")
    func analyticsReceivesEvents() async {
        let analytics = MockThermalAnalytics()
        let controller = makeController(analytics: analytics)

        await controller.setActiveShader("test")
        controller.checkNow()
        controller.checkNow()

        #expect(analytics.recordedEvents.count == 2)
        #expect(analytics.recordedEvents.first?.shaderId == "test")
    }

    // MARK: - External Factor Tests

    @Test("Low power mode forces aggressive throttle")
    func lowPowerModeThrottle() async {
        let context = MockThermalContext(thermalState: .nominal, isLowPowerMode: true)
        let controller = makeController(context: context)

        await controller.setActiveShader("test")
        controller.checkNow()

        #expect(controller.currentWallpaperFPS == ThermalContext.lowPowerWallpaperFPS)
        #expect(controller.currentScale == ThermalContext.lowPowerScale)
        #expect(controller.currentLOD == ThermalProfile.lodRange.lowerBound)
    }

    @Test("Charging suppresses profile persistence")
    func chargingSuppressesPersistence() async {
        let suiteName = "ChargingTest-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = ThermalProfileStore(defaults: defaults)
        let context = MockThermalContext(thermalState: .serious, isCharging: true)

        let controller = AdaptiveThermalController(
            store: store,
            context: context,
            optimizationInterval: .milliseconds(10),
            backgroundThreshold: 1
        )

        await controller.setActiveShader("test")

        // Run many ticks to trigger persistence check (every 12 ticks)
        for _ in 0..<24 {
            controller.checkNow()
        }

        // Check UserDefaults directly - profile should not be persisted when charging
        // store.load always returns a profile (default if not saved), so check defaults directly
        let key = "thermal_profile_test"
        #expect(defaults.data(forKey: key) == nil)
    }

    @Test("Quality recovery when thermal stable")
    func qualityRecoveryWhenStable() async {
        let context = MockThermalContext(thermalState: .nominal)
        let controller = makeController(context: context)

        await controller.setActiveShader("test")

        // Record baseline
        controller.checkNow()

        // Heat up progressively to build momentum
        context.thermalState = .fair
        controller.checkNow()
        context.thermalState = .serious
        controller.checkNow()
        context.thermalState = .critical
        controller.checkNow()
        controller.checkNow()
        controller.checkNow()

        let throttledFPS = controller.currentWallpaperFPS
        let throttledScale = controller.currentScale
        let throttledLOD = controller.currentLOD

        // Ensure we've actually throttled down
        #expect(throttledFPS < 60.0)
        #expect(throttledScale < 1.0)
        #expect(throttledLOD < 1.0)

        // Cool down progressively
        context.thermalState = .serious
        controller.checkNow()
        context.thermalState = .fair
        controller.checkNow()
        context.thermalState = .nominal
        controller.checkNow()

        // Run ticks for quality recovery (when momentum is in dead zone)
        for _ in 0..<10 {
            controller.checkNow()
        }

        // Should have recovered some quality
        #expect(controller.currentWallpaperFPS > throttledFPS)
        #expect(controller.currentScale > throttledScale)
        #expect(controller.currentLOD > throttledLOD)
    }

    // MARK: - Thermal Continuity Tests

    @Test("Foreground seeds thermal state when device is hot")
    func foregroundSeedsThermalState() async {
        let context = MockThermalContext(thermalState: .serious)
        let controller = makeController(context: context)

        await controller.setActiveShader("test")

        // Background and foreground with hot device
        controller.handleBackgrounded()
        controller.handleForegrounded()

        // Should immediately reflect the serious thermal state
        #expect(controller.rawThermalState == .serious)
        // Momentum should be seeded (0.67 × 0.3 = 0.201)
        #expect(controller.currentMomentum > 0.1)
    }

    @Test("Foreground with nominal device has zero momentum")
    func foregroundWithNominalDevice() async {
        let context = MockThermalContext(thermalState: .nominal)
        let controller = makeController(context: context)

        await controller.setActiveShader("test")

        // Heat up then cool down while backgrounded
        context.thermalState = .critical
        controller.checkNow()

        controller.handleBackgrounded()

        // Device cooled while backgrounded
        context.thermalState = .nominal

        controller.handleForegrounded()

        // Should have zero momentum since device is nominal
        #expect(controller.rawThermalState == .nominal)
        #expect(controller.currentMomentum == 0)
    }

    @Test("Wallpaper switch while hot applies thermal adjustment")
    func wallpaperSwitchWhileHot() async {
        // Start with device already at elevated thermal state
        let context = MockThermalContext(thermalState: .serious)
        let controller = makeController(context: context)

        // Set up first shader - device is already hot
        await controller.setActiveShader("shader1")
        controller.checkNow()

        // Switch to a new shader while device is still hot
        // The new shader has never been used, so its stored profile is max quality (60, 1.0, 1.0)
        await controller.setActiveShader("shader2")

        // New shader should NOT be at max quality - should be adjusted for thermal state
        // With .serious state (0.67 normalized), should have noticeable reduction
        #expect(controller.currentWallpaperFPS < 60.0, "Should not be at max FPS when device is hot")
        #expect(controller.currentScale < 1.0, "Should not be at max scale when device is hot")
        #expect(controller.currentLOD < 1.0, "Should not be at max LOD when device is hot")
    }

    @Test("Wallpaper switch while nominal uses stored profile")
    func wallpaperSwitchWhileNominal() async {
        let context = MockThermalContext(thermalState: .nominal)
        let controller = makeController(context: context)

        await controller.setActiveShader("shader1")
        controller.checkNow()

        // Switch while device is cool
        await controller.setActiveShader("shader2")

        // Should use max quality since device is nominal
        #expect(controller.currentWallpaperFPS == 60.0)
        #expect(controller.currentScale == 1.0)
        #expect(controller.currentLOD == 1.0)
    }

    @Test("Wallpaper switch preserves learned profile when device is hot")
    func wallpaperSwitchPreservesLearnedProfile() async {
        let suiteName = "LearnedProfile-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = ThermalProfileStore(defaults: defaults)
        let context = MockThermalContext(thermalState: .nominal)

        let controller = AdaptiveThermalController(
            store: store,
            context: context,
            optimizationInterval: .milliseconds(10),
            backgroundThreshold: 1
        )

        // Set up shader2 first and throttle it
        await controller.setActiveShader("shader2")
        controller.checkNow()

        // Build thermal momentum on shader2
        context.thermalState = .fair
        controller.checkNow()
        context.thermalState = .serious
        controller.checkNow()
        context.thermalState = .critical
        controller.checkNow()
        controller.checkNow()

        let shader2ThrottledScale = controller.currentScale

        // Background to persist the profile
        controller.handleBackgrounded()

        // Switch to shader1
        context.thermalState = .nominal
        controller.handleForegrounded()
        await controller.setActiveShader("shader1")

        // Heat up again
        context.thermalState = .serious
        controller.checkNow()
        controller.checkNow()

        // Switch back to shader2 while hot
        await controller.setActiveShader("shader2")

        // Should use the learned throttled profile (more conservative than default)
        #expect(controller.currentScale <= shader2ThrottledScale)
    }
}
