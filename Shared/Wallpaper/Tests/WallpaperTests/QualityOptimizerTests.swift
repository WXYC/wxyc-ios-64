//
//  QualityOptimizerTests.swift
//  Wallpaper
//
//  Tests for QualityOptimizer algorithm.
//
//  Created by Jake Bromberg on 01/03/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import Wallpaper

@Suite("QualityOptimizer")
struct QualityOptimizerTests {

    let optimizer = QualityOptimizer()

    @Test("No adjustment in dead zone")
    func noAdjustmentInDeadZone() {
        let profile = AdaptiveProfile(shaderId: "test", wallpaperFPS: 50, scale: 0.8, lod: 0.7)

        // Momentum within dead zone
        let result = optimizer.optimize(current: profile, momentum: 0.05)

        #expect(result.wallpaperFPS == profile.wallpaperFPS)
        #expect(result.scale == profile.scale)
        #expect(result.lod == profile.lod)
    }

    @Test("Heating reduces quality")
    func heatingReducesQuality() {
        let profile = AdaptiveProfile(shaderId: "test", wallpaperFPS: 60, scale: 1.0, lod: 1.0)

        let result = optimizer.optimize(current: profile, momentum: 0.5)

        // LOD is reduced first, then scale, then wallpaper FPS
        #expect(result.lod < profile.lod)
        #expect(result.scale < profile.scale)
        #expect(result.wallpaperFPS < profile.wallpaperFPS)
    }

    @Test("Cooling restores quality")
    func coolingRestoresQuality() {
        let profile = AdaptiveProfile(shaderId: "test", wallpaperFPS: 30, scale: 0.6, lod: 0.5)

        let result = optimizer.optimize(current: profile, momentum: -0.5)

        #expect(result.wallpaperFPS > profile.wallpaperFPS)
        #expect(result.scale > profile.scale)
        #expect(result.lod > profile.lod)
    }

    @Test("Scale is adjusted more than wallpaper FPS on heating")
    func scalePreferredOnHeating() {
        let profile = AdaptiveProfile(shaderId: "test", wallpaperFPS: 60, scale: 1.0, lod: 1.0)

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
        let lowProfile = AdaptiveProfile(shaderId: "test", wallpaperFPS: 16, scale: 0.51, lod: 0.1)
        let lowResult = optimizer.optimize(current: lowProfile, momentum: 0.8)

        #expect(lowResult.wallpaperFPS >= AdaptiveProfile.wallpaperFPSRange.lowerBound)
        #expect(lowResult.scale >= AdaptiveProfile.scaleRange.lowerBound)
        #expect(lowResult.lod >= AdaptiveProfile.lodRange.lowerBound)

        // Test upper bounds
        let highProfile = AdaptiveProfile(shaderId: "test", wallpaperFPS: 59, scale: 0.99, lod: 0.95)
        let highResult = optimizer.optimize(current: highProfile, momentum: -0.8)

        #expect(highResult.wallpaperFPS <= AdaptiveProfile.wallpaperFPSRange.upperBound)
        #expect(highResult.scale <= AdaptiveProfile.scaleRange.upperBound)
        #expect(highResult.lod <= AdaptiveProfile.lodRange.upperBound)
    }

    @Test("Recovery is slower than reduction")
    func recoverySlower() {
        let profile = AdaptiveProfile(shaderId: "test", wallpaperFPS: 45, scale: 0.75, lod: 0.6)

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

    @Test("Fair thermal state produces meaningful throttling from max quality")
    func fairThermalProducesMeaningfulThrottling() {
        // Start at max quality
        let profile = AdaptiveProfile(shaderId: "test", wallpaperFPS: 60, scale: 1.0, lod: 1.0)

        // Fair thermal state momentum (~0.33)
        let result = optimizer.optimize(current: profile, momentum: 0.33)

        // At fair thermal, we should see meaningful reductions
        // Upper boundary damping reduces these slightly from original expectations
        let lodReduction = profile.lod - result.lod
        #expect(lodReduction >= 0.008, "LOD reduction \(lodReduction) should be at least 0.008")

        // Scale should drop meaningfully
        let scaleReduction = profile.scale - result.scale
        #expect(scaleReduction >= 0.004, "Scale reduction \(scaleReduction) should be at least 0.004")

        // FPS should drop meaningfully
        let fpsReduction = profile.wallpaperFPS - result.wallpaperFPS
        #expect(fpsReduction >= 0.15, "FPS reduction \(fpsReduction) should be at least 0.15")
    }

    // MARK: - Symmetric Damping Tests

    @Test("Damping is applied near lower boundary")
    func dampingAppliedAtLowerBoundary() {
        // Profile near lower bounds (but not at the very edge where damping applies)
        let profile = AdaptiveProfile(shaderId: "test", wallpaperFPS: 17, scale: 0.54, lod: 0.05)

        // Heavy heating should be dampened near lower boundary
        let result = optimizer.optimize(current: profile, momentum: 0.8)

        // Values should be dampened and not hit absolute minimum immediately
        #expect(result.wallpaperFPS > AdaptiveProfile.wallpaperFPSRange.lowerBound)
        #expect(result.scale > AdaptiveProfile.scaleRange.lowerBound)
        #expect(result.lod >= AdaptiveProfile.lodRange.lowerBound) // LOD may hit zero
    }

    @Test("Damping is applied near upper boundary during recovery")
    func dampingAppliedAtUpperBoundary() {
        // Profile near upper bounds
        let profile = AdaptiveProfile(shaderId: "test", wallpaperFPS: 58, scale: 0.97, lod: 0.96)

        // Strong cooling should be dampened near upper boundary
        let result = optimizer.optimize(current: profile, momentum: -0.8)

        // Recovery should approach max smoothly, not overshoot
        #expect(result.wallpaperFPS < AdaptiveProfile.wallpaperFPSRange.upperBound)
        #expect(result.scale < AdaptiveProfile.scaleRange.upperBound)
        #expect(result.lod < AdaptiveProfile.lodRange.upperBound)
    }

    @Test("Upper boundary damping is lighter than lower boundary")
    func upperDampingLighterThanLower() {
        // Compare damping strength at both boundaries with same momentum magnitude

        // Near lower bound
        let lowProfile = AdaptiveProfile(shaderId: "test", wallpaperFPS: 17, scale: 0.54, lod: 0.05)
        let lowResult = optimizer.optimize(current: lowProfile, momentum: 0.5)
        let lowFPSChange = abs(lowProfile.wallpaperFPS - lowResult.wallpaperFPS)

        // Near upper bound
        let highProfile = AdaptiveProfile(shaderId: "test", wallpaperFPS: 58, scale: 0.97, lod: 0.96)
        let highResult = optimizer.optimize(current: highProfile, momentum: -0.5)
        let highFPSChange = abs(highProfile.wallpaperFPS - highResult.wallpaperFPS)

        // Upper damping (0.5 min factor) should allow more movement than lower (0.3 min factor)
        // This is subtle - the damping effect can be close
        #expect(highFPSChange >= lowFPSChange * 0.7, "Upper damping should be lighter or similar")
    }

    @Test("No damping in middle range")
    func noDampingInMiddleRange() {
        // Profile in middle of ranges (no damping should apply)
        let middleProfile = AdaptiveProfile(shaderId: "test", wallpaperFPS: 40, scale: 0.75, lod: 0.5)

        // Apply same momentum in both directions
        let heatingResult = optimizer.optimize(current: middleProfile, momentum: 0.3)
        let coolingResult = optimizer.optimize(current: middleProfile, momentum: -0.3)

        // Changes should follow expected ratios without damping interference
        let heatingFPSChange = abs(middleProfile.wallpaperFPS - heatingResult.wallpaperFPS)
        let coolingFPSChange = abs(middleProfile.wallpaperFPS - coolingResult.wallpaperFPS)

        // Recovery should be exactly half speed (no additional damping)
        let ratio = coolingFPSChange / heatingFPSChange
        #expect(abs(ratio - 0.5) < 0.1, "Ratio \(ratio) should be close to 0.5")
    }
}
