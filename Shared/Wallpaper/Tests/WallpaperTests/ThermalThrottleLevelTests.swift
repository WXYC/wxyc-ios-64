import Foundation
import Testing
@testable import Wallpaper

@Suite("ThermalThrottleLevel")
struct ThermalThrottleLevelTests {

    @Test("Resolution scale values are correct")
    func resolutionScaleValues() {
        #expect(ThermalThrottleLevel.nominal.resolutionScale == 1.0)
        #expect(ThermalThrottleLevel.fair.resolutionScale == 0.75)
        #expect(ThermalThrottleLevel.serious.resolutionScale == 0.5)
        #expect(ThermalThrottleLevel.critical.resolutionScale == 0.5)
    }

    @Test("Target FPS values are correct")
    func fpsValues() {
        #expect(ThermalThrottleLevel.nominal.targetFPS == 60)
        #expect(ThermalThrottleLevel.fair.targetFPS == 60)
        #expect(ThermalThrottleLevel.serious.targetFPS == 30)
        #expect(ThermalThrottleLevel.critical.targetFPS == 15)
    }

    @Test("Thermal state mapping is correct")
    func thermalStateMapping() {
        #expect(ThermalThrottleLevel(thermalState: .nominal) == .nominal)
        #expect(ThermalThrottleLevel(thermalState: .fair) == .fair)
        #expect(ThermalThrottleLevel(thermalState: .serious) == .serious)
        #expect(ThermalThrottleLevel(thermalState: .critical) == .critical)
    }

    @Test("isWorseThan comparison is correct")
    func isWorseThan() {
        // Each level is worse than levels before it
        #expect(ThermalThrottleLevel.fair.isWorseThan(.nominal))
        #expect(ThermalThrottleLevel.serious.isWorseThan(.nominal))
        #expect(ThermalThrottleLevel.serious.isWorseThan(.fair))
        #expect(ThermalThrottleLevel.critical.isWorseThan(.nominal))
        #expect(ThermalThrottleLevel.critical.isWorseThan(.fair))
        #expect(ThermalThrottleLevel.critical.isWorseThan(.serious))

        // Same level is not worse
        #expect(!ThermalThrottleLevel.nominal.isWorseThan(.nominal))
        #expect(!ThermalThrottleLevel.fair.isWorseThan(.fair))

        // Better levels are not worse
        #expect(!ThermalThrottleLevel.nominal.isWorseThan(.fair))
        #expect(!ThermalThrottleLevel.nominal.isWorseThan(.critical))
    }

    @Test("isBetterThan comparison is correct")
    func isBetterThan() {
        // Each level is better than levels after it
        #expect(ThermalThrottleLevel.nominal.isBetterThan(.fair))
        #expect(ThermalThrottleLevel.nominal.isBetterThan(.serious))
        #expect(ThermalThrottleLevel.nominal.isBetterThan(.critical))
        #expect(ThermalThrottleLevel.fair.isBetterThan(.serious))
        #expect(ThermalThrottleLevel.fair.isBetterThan(.critical))
        #expect(ThermalThrottleLevel.serious.isBetterThan(.critical))

        // Same level is not better
        #expect(!ThermalThrottleLevel.nominal.isBetterThan(.nominal))
        #expect(!ThermalThrottleLevel.critical.isBetterThan(.critical))

        // Worse levels are not better
        #expect(!ThermalThrottleLevel.critical.isBetterThan(.nominal))
        #expect(!ThermalThrottleLevel.serious.isBetterThan(.fair))
    }

    @Test("nextBetterLevel returns correct progression")
    func nextBetterLevel() {
        #expect(ThermalThrottleLevel.critical.nextBetterLevel == .serious)
        #expect(ThermalThrottleLevel.serious.nextBetterLevel == .fair)
        #expect(ThermalThrottleLevel.fair.nextBetterLevel == .nominal)
        #expect(ThermalThrottleLevel.nominal.nextBetterLevel == .nominal)
    }
}
