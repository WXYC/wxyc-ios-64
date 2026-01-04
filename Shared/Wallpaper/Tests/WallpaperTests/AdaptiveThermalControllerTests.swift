import Foundation
import Testing
@testable import Wallpaper

@Suite("AdaptiveThermalController")
@MainActor
struct AdaptiveThermalControllerTests {

    /// Creates a test controller with injectable thermal state.
    func makeController(
        thermalState: @escaping @Sendable () -> ProcessInfo.ThermalState = { .nominal },
        analytics: ThermalAnalytics? = nil
    ) -> AdaptiveThermalController {
        let defaults = UserDefaults(suiteName: "AdaptiveThermalControllerTests-\(UUID().uuidString)")!
        let store = ThermalProfileStore(defaults: defaults)

        return AdaptiveThermalController(
            store: store,
            optimizer: ThermalOptimizer(),
            analytics: analytics,
            thermalStateProvider: thermalState,
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
        nonisolated(unsafe) var mockState: ProcessInfo.ThermalState = .nominal
        let controller = makeController(thermalState: { mockState })

        await controller.setActiveShader("test")

        // Simulate heating
        mockState = .serious
        controller.checkNow()
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
        nonisolated(unsafe) var mockState: ProcessInfo.ThermalState = .critical
        let controller = makeController(thermalState: { mockState })

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
        mockState = .nominal

        // Foreground
        controller.handleForegrounded()

        // Should have some recovery bonus
        #expect(controller.currentFPS >= throttledFPS)
        #expect(controller.currentScale >= throttledScale)
    }

    @Test("checkNow updates thermal state")
    func checkNowUpdatesThermalState() async {
        nonisolated(unsafe) var mockState: ProcessInfo.ThermalState = .nominal
        let controller = makeController(thermalState: { mockState })

        await controller.setActiveShader("test")

        mockState = .serious
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
}
