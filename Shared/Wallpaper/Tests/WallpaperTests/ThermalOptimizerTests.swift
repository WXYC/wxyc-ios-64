import Foundation
import Testing
@testable import Wallpaper

@Suite("ThermalOptimizer")
struct ThermalOptimizerTests {

    let optimizer = ThermalOptimizer()

    @Test("No adjustment in dead zone")
    func noAdjustmentInDeadZone() {
        let profile = ThermalProfile(shaderId: "test", fps: 50, scale: 0.8)

        // Momentum within dead zone
        let result = optimizer.optimize(current: profile, momentum: 0.05)

        #expect(result.fps == profile.fps)
        #expect(result.scale == profile.scale)
    }

    @Test("Heating reduces quality")
    func heatingReducesQuality() {
        let profile = ThermalProfile(shaderId: "test", fps: 60, scale: 1.0)

        let result = optimizer.optimize(current: profile, momentum: 0.5)

        #expect(result.fps < profile.fps)
        #expect(result.scale < profile.scale)
    }

    @Test("Cooling restores quality")
    func coolingRestoresQuality() {
        let profile = ThermalProfile(shaderId: "test", fps: 30, scale: 0.6)

        let result = optimizer.optimize(current: profile, momentum: -0.5)

        #expect(result.fps > profile.fps)
        #expect(result.scale > profile.scale)
    }

    @Test("Scale is adjusted more than FPS on heating")
    func scalePreferredOnHeating() {
        let profile = ThermalProfile(shaderId: "test", fps: 60, scale: 1.0)

        let result = optimizer.optimize(current: profile, momentum: 0.3)

        let fpsReduction = profile.fps - result.fps
        let scaleReduction = profile.scale - result.scale

        // Scale should be reduced proportionally more (70% weight)
        // Normalize scale to FPS-equivalent for comparison
        let normalizedScaleReduction = scaleReduction * 60

        #expect(normalizedScaleReduction > fpsReduction)
    }

    @Test("Results are clamped to valid ranges")
    func resultsClamped() {
        // Test lower bounds
        let lowProfile = ThermalProfile(shaderId: "test", fps: 16, scale: 0.51)
        let lowResult = optimizer.optimize(current: lowProfile, momentum: 0.8)

        #expect(lowResult.fps >= ThermalProfile.fpsRange.lowerBound)
        #expect(lowResult.scale >= ThermalProfile.scaleRange.lowerBound)

        // Test upper bounds
        let highProfile = ThermalProfile(shaderId: "test", fps: 59, scale: 0.99)
        let highResult = optimizer.optimize(current: highProfile, momentum: -0.8)

        #expect(highResult.fps <= ThermalProfile.fpsRange.upperBound)
        #expect(highResult.scale <= ThermalProfile.scaleRange.upperBound)
    }

    @Test("Recovery is slower than reduction")
    func recoverySlower() {
        let profile = ThermalProfile(shaderId: "test", fps: 45, scale: 0.75)

        // Same magnitude momentum, opposite directions
        let heatingResult = optimizer.optimize(current: profile, momentum: 0.5)
        let coolingResult = optimizer.optimize(current: profile, momentum: -0.5)

        let heatingFPSChange = abs(profile.fps - heatingResult.fps)
        let coolingFPSChange = abs(profile.fps - coolingResult.fps)

        let heatingScaleChange = abs(profile.scale - heatingResult.scale)
        let coolingScaleChange = abs(profile.scale - coolingResult.scale)

        // Cooling changes should be smaller (half speed)
        #expect(coolingFPSChange < heatingFPSChange)
        #expect(coolingScaleChange < heatingScaleChange)
    }
}
