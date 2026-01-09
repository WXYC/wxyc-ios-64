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

        #expect(controller.currentFPS == 60.0)
        #expect(controller.currentScale == 1.0)
        #expect(controller.currentLOD == 1.0)
        #expect(controller.activeShaderID == nil)
    }

    @Test("setActiveShader loads profile")
    func setActiveShaderLoadsProfile() async {
        let controller = makeController()

        await controller.setActiveShader("test_shader")

        #expect(controller.activeShaderID == "test_shader")
        #expect(controller.currentFPS == 60.0)
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

        #expect(controller.currentFPS < 60.0)
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

        let throttledFPS = controller.currentFPS
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
        #expect(controller.currentFPS >= throttledFPS)
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

        #expect(controller.currentFPS == ThermalContext.lowPowerFPS)
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

    @Test("Critical FPS drops LOD and scale but keeps FPS target high")
    func criticalFPSDropsScale() async {
        let context = MockThermalContext(thermalState: .nominal)
        let controller = makeController(context: context)

        await controller.setActiveShader("test")

        // Start at max quality
        #expect(controller.currentFPS == 60.0)
        #expect(controller.currentScale == 1.0)
        #expect(controller.currentLOD == 1.0)

        // Report critical FPS (< 25) - GPU can't keep up
        controller.reportMeasuredFPS(15.0)

        // Should drop LOD and scale to reduce workload, but keep FPS target high
        #expect(controller.currentFPS == 60.0)  // Keep high - we want smooth animation
        #expect(controller.currentScale == ThermalProfile.scaleRange.lowerBound)  // Drop scale
        #expect(controller.currentLOD == ThermalProfile.lodRange.lowerBound)  // Drop LOD
        #expect(controller.currentMomentum == 1.0)
    }

    @Test("Low FPS reduces all axes proportionally")
    func lowFPSReducesProportionally() async {
        let context = MockThermalContext(thermalState: .nominal)
        let controller = makeController(context: context)

        await controller.setActiveShader("test")

        // Start at max quality
        #expect(controller.currentFPS == 60.0)
        #expect(controller.currentScale == 1.0)
        #expect(controller.currentLOD == 1.0)

        // Report low FPS (warning level, 25-50)
        controller.reportMeasuredFPS(40.0)

        // Should reduce all three axes proportionally (not just LOD)
        #expect(controller.currentLOD < 1.0)
        #expect(controller.currentScale < 1.0)
        #expect(controller.currentFPS < 60.0)
    }

    @Test("Low FPS reduces FPS target when LOD and scale at minimum")
    func lowFPSReducesFPSTargetAtMinScale() async {
        let context = MockThermalContext(thermalState: .nominal)
        let controller = makeController(context: context)

        await controller.setActiveShader("test")

        // Force LOD and scale to minimum first
        controller.reportMeasuredFPS(15.0)  // Critical - drops LOD and scale to min
        #expect(controller.currentLOD == ThermalProfile.lodRange.lowerBound)
        #expect(controller.currentScale == ThermalProfile.scaleRange.lowerBound)
        #expect(controller.currentFPS == 60.0)

        // Now report low FPS again - LOD and scale can't go lower, so FPS should drop
        controller.reportMeasuredFPS(40.0)

        // FPS target should be reduced since LOD and scale are at minimum
        #expect(controller.currentFPS < 60.0)
        #expect(controller.currentLOD == ThermalProfile.lodRange.lowerBound)
        #expect(controller.currentScale == ThermalProfile.scaleRange.lowerBound)
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

        let throttledFPS = controller.currentFPS
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
        #expect(controller.currentFPS > throttledFPS)
        #expect(controller.currentScale > throttledScale)
        #expect(controller.currentLOD > throttledLOD)
    }
}
