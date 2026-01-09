import Foundation
import Testing
@testable import Wallpaper

@Suite("ThermalOptimizer")
struct ThermalOptimizerTests {

    let optimizer = ThermalOptimizer()

    @Test("No adjustment in dead zone")
    func noAdjustmentInDeadZone() {
        let profile = ThermalProfile(shaderId: "test", wallpaperFPS: 50, scale: 0.8, lod: 0.7)

        // Momentum within dead zone
        let result = optimizer.optimize(current: profile, momentum: 0.05)

        #expect(result.wallpaperFPS == profile.wallpaperFPS)
        #expect(result.scale == profile.scale)
        #expect(result.lod == profile.lod)
    }

    @Test("Heating reduces quality")
    func heatingReducesQuality() {
        let profile = ThermalProfile(shaderId: "test", wallpaperFPS: 60, scale: 1.0, lod: 1.0)

        let result = optimizer.optimize(current: profile, momentum: 0.5)

        // LOD is reduced first, then scale, then wallpaper FPS
        #expect(result.lod < profile.lod)
        #expect(result.scale < profile.scale)
        #expect(result.wallpaperFPS < profile.wallpaperFPS)
    }

    @Test("Cooling restores quality")
    func coolingRestoresQuality() {
        let profile = ThermalProfile(shaderId: "test", wallpaperFPS: 30, scale: 0.6, lod: 0.5)

        let result = optimizer.optimize(current: profile, momentum: -0.5)

        #expect(result.wallpaperFPS > profile.wallpaperFPS)
        #expect(result.scale > profile.scale)
        #expect(result.lod > profile.lod)
    }

    @Test("Scale is adjusted more than wallpaper FPS on heating")
    func scalePreferredOnHeating() {
        let profile = ThermalProfile(shaderId: "test", wallpaperFPS: 60, scale: 1.0, lod: 1.0)

        let result = optimizer.optimize(current: profile, momentum: 0.3)

        let fpsReduction = profile.wallpaperFPS - result.wallpaperFPS
        let scaleReduction = profile.scale - result.scale

        // Scale should be reduced proportionally more (60% weight vs 20% for wallpaper FPS)
        // Normalize scale to wallpaperFPS-equivalent for comparison
        let normalizedScaleReduction = scaleReduction * 60

        #expect(normalizedScaleReduction > fpsReduction)
    }

    @Test("Results are clamped to valid ranges")
    func resultsClamped() {
        // Test lower bounds
        let lowProfile = ThermalProfile(shaderId: "test", wallpaperFPS: 16, scale: 0.51, lod: 0.1)
        let lowResult = optimizer.optimize(current: lowProfile, momentum: 0.8)

        #expect(lowResult.wallpaperFPS >= ThermalProfile.wallpaperFPSRange.lowerBound)
        #expect(lowResult.scale >= ThermalProfile.scaleRange.lowerBound)
        #expect(lowResult.lod >= ThermalProfile.lodRange.lowerBound)

        // Test upper bounds
        let highProfile = ThermalProfile(shaderId: "test", wallpaperFPS: 59, scale: 0.99, lod: 0.95)
        let highResult = optimizer.optimize(current: highProfile, momentum: -0.8)

        #expect(highResult.wallpaperFPS <= ThermalProfile.wallpaperFPSRange.upperBound)
        #expect(highResult.scale <= ThermalProfile.scaleRange.upperBound)
        #expect(highResult.lod <= ThermalProfile.lodRange.upperBound)
    }

    @Test("Recovery is slower than reduction")
    func recoverySlower() {
        let profile = ThermalProfile(shaderId: "test", wallpaperFPS: 45, scale: 0.75, lod: 0.6)

        // Same magnitude momentum, opposite directions
        let heatingResult = optimizer.optimize(current: profile, momentum: 0.5)
        let coolingResult = optimizer.optimize(current: profile, momentum: -0.5)

        let heatingFPSChange = abs(profile.wallpaperFPS - heatingResult.wallpaperFPS)
        let coolingFPSChange = abs(profile.wallpaperFPS - coolingResult.wallpaperFPS)

        let heatingScaleChange = abs(profile.scale - heatingResult.scale)
        let coolingScaleChange = abs(profile.scale - coolingResult.scale)

        let heatingLODChange = abs(profile.lod - heatingResult.lod)
        let coolingLODChange = abs(profile.lod - coolingResult.lod)

        // Cooling changes should be smaller (half speed)
        #expect(coolingFPSChange < heatingFPSChange)
        #expect(coolingScaleChange < heatingScaleChange)
        #expect(coolingLODChange < heatingLODChange)
    }
}
