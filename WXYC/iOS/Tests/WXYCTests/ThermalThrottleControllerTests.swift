import Foundation
import Testing
@testable import Wallpaper

@Suite("ThermalThrottleController")
@MainActor
struct ThermalThrottleControllerTests {

    @Test("Initial state is nominal")
    func initialState() {
        let controller = ThermalThrottleController(
            thermalStateProvider: { .nominal },
            startMonitoringAutomatically: false
        )
        #expect(controller.currentLevel == .nominal)
        #expect(controller.rawThermalState == .nominal)
    }

    @Test("Immediate downgrade on thermal worsening")
    func immediateDowngrade() {
        nonisolated(unsafe) var mockState: ProcessInfo.ThermalState = .nominal
        let controller = ThermalThrottleController(
            thermalStateProvider: { mockState },
            startMonitoringAutomatically: false
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
            hysteresisDelay: .milliseconds(100),
            startMonitoringAutomatically: false
        )
        controller.checkThermalState()
        #expect(controller.currentLevel == .serious)

        // Thermal improves
        mockState = .nominal
        controller.checkThermalState()

        // Should still be serious (hysteresis)
        #expect(controller.currentLevel == .serious)
        #expect(controller.rawThermalState == .nominal)

        // Wait for hysteresis
        try await Task.sleep(for: .milliseconds(150))
        controller.checkHysteresisRecovery()

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

        // Still at critical
        #expect(controller.currentLevel == .critical)

        // Wait and recover one step
        try await Task.sleep(for: .milliseconds(60))
        controller.checkHysteresisRecovery()
        #expect(controller.currentLevel == .serious)

        // Wait and recover another step
        try await Task.sleep(for: .milliseconds(60))
        controller.checkHysteresisRecovery()
        #expect(controller.currentLevel == .fair)

        // Wait and recover to nominal
        try await Task.sleep(for: .milliseconds(60))
        controller.checkHysteresisRecovery()
        #expect(controller.currentLevel == .nominal)
    }

    @Test("Downgrade cancels pending upgrade")
    func downgradeCancelsPendingUpgrade() async throws {
        nonisolated(unsafe) var mockState: ProcessInfo.ThermalState = .fair
        let controller = ThermalThrottleController(
            thermalStateProvider: { mockState },
            hysteresisDelay: .milliseconds(500),
            startMonitoringAutomatically: false
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

        // Even after waiting, should stay at serious
        try await Task.sleep(for: .milliseconds(100))
        controller.checkHysteresisRecovery()
        #expect(controller.currentLevel == .serious)
    }

    @Test("No change when thermal state unchanged")
    func noChangeWhenUnchanged() {
        let mockState: ProcessInfo.ThermalState = .fair
        let controller = ThermalThrottleController(
            thermalStateProvider: { mockState },
            startMonitoringAutomatically: false
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
            thermalStateProvider: { mockState },
            startMonitoringAutomatically: false
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

    @Test("AsyncStream yields level changes")
    func asyncStreamYieldsChanges() async {
        nonisolated(unsafe) var mockState: ProcessInfo.ThermalState = .nominal
        let controller = ThermalThrottleController(
            thermalStateProvider: { mockState },
            startMonitoringAutomatically: false
        )

        var receivedLevels: [ThermalThrottleLevel] = []
        let expectation = Task {
            for await level in controller.levelChanges {
                receivedLevels.append(level)
                if receivedLevels.count >= 3 {
                    break
                }
            }
        }

        // Give the stream time to set up
        try? await Task.sleep(for: .milliseconds(10))

        // Trigger changes
        mockState = .fair
        controller.checkThermalState()

        mockState = .serious
        controller.checkThermalState()

        // Wait for stream to receive values
        try? await Task.sleep(for: .milliseconds(50))
        expectation.cancel()

        #expect(receivedLevels.contains(.nominal))
        #expect(receivedLevels.contains(.fair))
        #expect(receivedLevels.contains(.serious))
    }
}
