import Foundation
import Testing
@testable import Wallpaper

@Suite("AdaptiveThermalController")
@MainActor
struct AdaptiveThermalControllerTests {

    /// Creates a test controller with injectable context.
    func makeController(
        context: ThermalContextProtocol = MockThermalContext(),
        analytics: ThermalAnalytics? = nil
    ) -> AdaptiveThermalController {
        let defaults = UserDefaults(suiteName: "AdaptiveThermalControllerTests-\(UUID().uuidString)")!
        let store = ThermalProfileStore(defaults: defaults)

        return AdaptiveThermalController(
            store: store,
            optimizer: ThermalOptimizer(),
            analytics: analytics,
            context: context,
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
        #expect(controller.activeShaderID == nil)
    }

    @Test("setActiveShader loads profile")
    func setActiveShaderLoadsProfile() async {
        let controller = makeController()

        await controller.setActiveShader("test_shader")

        #expect(controller.activeShaderID == "test_shader")
        #expect(controller.currentFPS == 60.0)
        #expect(controller.currentScale == 1.0)
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
    func foregroundAppliesCooldownBonus() async throws {
        let context = MockThermalContext(thermalState: .critical)
        let controller = makeController(context: context)

        await controller.setActiveShader("test")

        // Heat up
        controller.checkNow()
        controller.checkNow()
        controller.checkNow()

        let throttledFPS = controller.currentFPS
        let throttledScale = controller.currentScale

        // Background
        controller.handleBackgrounded()

        // Wait for "long" background (> 1 second in our test config)
        try await Task.sleep(for: .seconds(1.5))

        // Cool down while backgrounded
        context.thermalState = .nominal

        // Foreground
        controller.handleForegrounded()

        // Should have some recovery bonus
        #expect(controller.currentFPS >= throttledFPS)
        #expect(controller.currentScale >= throttledScale)
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

    @Test("Critical FPS drops scale but keeps FPS target high")
    func criticalFPSDropsScale() async {
        let context = MockThermalContext(thermalState: .nominal)
        let controller = makeController(context: context)

        await controller.setActiveShader("test")

        // Start at max quality
        #expect(controller.currentFPS == 60.0)
        #expect(controller.currentScale == 1.0)

        // Report critical FPS (< 25) - GPU can't keep up
        controller.reportMeasuredFPS(15.0)

        // Should drop scale to reduce workload, but keep FPS target high
        #expect(controller.currentFPS == 60.0)  // Keep high - we want smooth animation
        #expect(controller.currentScale == ThermalProfile.scaleRange.lowerBound)  // Drop scale
        #expect(controller.currentMomentum == 1.0)
    }

    @Test("Low FPS reduces scale when above minimum")
    func lowFPSReducesScale() async {
        let context = MockThermalContext(thermalState: .nominal)
        let controller = makeController(context: context)

        await controller.setActiveShader("test")

        // Start at max quality
        #expect(controller.currentFPS == 60.0)
        #expect(controller.currentScale == 1.0)

        // Report low FPS (warning level, 25-50)
        controller.reportMeasuredFPS(40.0)

        // Should reduce scale, keep FPS target high
        #expect(controller.currentFPS == 60.0)
        #expect(controller.currentScale < 1.0)
    }

    @Test("Low FPS reduces FPS target when scale at minimum")
    func lowFPSReducesFPSTargetAtMinScale() async {
        let context = MockThermalContext(thermalState: .nominal)
        let controller = makeController(context: context)

        await controller.setActiveShader("test")

        // Force scale to minimum first
        controller.reportMeasuredFPS(15.0)  // Critical - drops scale to min
        #expect(controller.currentScale == ThermalProfile.scaleRange.lowerBound)
        #expect(controller.currentFPS == 60.0)

        // Now report low FPS again - scale can't go lower, so FPS should drop
        controller.reportMeasuredFPS(40.0)

        // FPS target should be reduced since scale is at minimum
        #expect(controller.currentFPS < 60.0)
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

        // Ensure we've actually throttled down
        #expect(throttledFPS < 60.0)
        #expect(throttledScale < 1.0)

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
    }
}
