import Foundation
import Testing
@testable import Wallpaper

@Suite("ThermalThrottleController")
@MainActor
struct ThermalThrottleControllerTests {

    @Test("Initial state is nominal")
    func initialState() {
        let controller = ThermalThrottleController(
            thermalStateProvider: { .nominal }
        )
        #expect(controller.currentLevel == .nominal)
        #expect(controller.rawThermalState == .nominal)
    }

    @Test("Immediate downgrade on thermal worsening")
    func immediateDowngrade() {
        nonisolated(unsafe) var mockState: ProcessInfo.ThermalState = .nominal
        let controller = ThermalThrottleController(
            thermalStateProvider: { mockState }
        )

        #expect(controller.currentLevel == .nominal)

        mockState = .serious
        controller.checkThermalState()

        #expect(controller.currentLevel == .serious)
        #expect(controller.rawThermalState == .serious)
    }

    @Test("Delayed upgrade with hysteresis")
    func delayedUpgrade() async throws {
        nonisolated(unsafe) var mockState: ProcessInfo.ThermalState = .serious
        let controller = ThermalThrottleController(
            thermalStateProvider: { mockState },
            hysteresisDelay: .milliseconds(100)
        )
        controller.checkThermalState()
        #expect(controller.currentLevel == .serious)

        // Thermal improves
        mockState = .nominal
        controller.checkThermalState()

        // Should still be serious (hysteresis)
        #expect(controller.currentLevel == .serious)
        #expect(controller.rawThermalState == .nominal)

        // Wait for hysteresis (scheduled task will run after 100ms and step up to .fair)
        try await Task.sleep(for: .milliseconds(200))

        // Should step up one level (serious -> fair), not jump to nominal
        #expect(controller.currentLevel == .fair)
    }

    @Test("Steps up one level at a time")
    func stepsUpOneLevel() async throws {
        nonisolated(unsafe) var mockState: ProcessInfo.ThermalState = .critical
        let controller = ThermalThrottleController(
            thermalStateProvider: { mockState },
            hysteresisDelay: .milliseconds(50),
            startMonitoringAutomatically: false
        )
        controller.checkThermalState()
        #expect(controller.currentLevel == .critical)

        // Thermal jumps to nominal
        mockState = .nominal
        controller.checkThermalState()

        // Still at critical (hysteresis not elapsed)
        #expect(controller.currentLevel == .critical)

        // Wait for hysteresis and recover one step
        // Use 65ms to avoid race with next hysteresis at 100ms
        try await Task.sleep(for: .milliseconds(65))
        #expect(controller.currentLevel == .serious)

        // Wait and recover another step (65ms more puts us at 130ms, after 100ms hysteresis)
        try await Task.sleep(for: .milliseconds(65))
        #expect(controller.currentLevel == .fair)

        // Wait and recover to nominal (130+65=195ms, after 150ms hysteresis)
        try await Task.sleep(for: .milliseconds(65))
        #expect(controller.currentLevel == .nominal)
    }

    @Test("Downgrade cancels pending upgrade")
    func downgradeCancelsPendingUpgrade() async throws {
        nonisolated(unsafe) var mockState: ProcessInfo.ThermalState = .fair
        let controller = ThermalThrottleController(
            thermalStateProvider: { mockState },
            hysteresisDelay: .milliseconds(500)
        )
        controller.checkThermalState()
        #expect(controller.currentLevel == .fair)

        // Improve to nominal - starts hysteresis timer
        mockState = .nominal
        controller.checkThermalState()
        #expect(controller.currentLevel == .fair)

        // Before hysteresis completes, worsen again
        mockState = .serious
        controller.checkThermalState()

        // Should be at serious, hysteresis cancelled
        #expect(controller.currentLevel == .serious)

        // Even after waiting, should stay at serious (no improvement since state is serious)
        try await Task.sleep(for: .milliseconds(100))
        #expect(controller.currentLevel == .serious)
    }

    @Test("No change when thermal state unchanged")
    func noChangeWhenUnchanged() {
        nonisolated(unsafe) let mockState: ProcessInfo.ThermalState = .fair
        let controller = ThermalThrottleController(
            thermalStateProvider: { mockState }
        )
        controller.checkThermalState()
        #expect(controller.currentLevel == .fair)

        // Check again with same state
        controller.checkThermalState()
        #expect(controller.currentLevel == .fair)
    }

    @Test("Multiple rapid downgrades")
    func rapidDowngrades() {
        nonisolated(unsafe) var mockState: ProcessInfo.ThermalState = .nominal
        let controller = ThermalThrottleController(
            thermalStateProvider: { mockState }
        )

        mockState = .fair
        controller.checkThermalState()
        #expect(controller.currentLevel == .fair)

        mockState = .serious
        controller.checkThermalState()
        #expect(controller.currentLevel == .serious)

        mockState = .critical
        controller.checkThermalState()
        #expect(controller.currentLevel == .critical)
    }
}
