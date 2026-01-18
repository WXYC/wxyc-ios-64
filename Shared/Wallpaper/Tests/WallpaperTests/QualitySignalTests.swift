//
//  QualitySignalTests.swift
//  Wallpaper
//
//  Tests for QualitySignal processing.
//
//  Created by Jake Bromberg on 01/03/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import Wallpaper

@Suite("QualitySignal")
struct QualitySignalTests {

    @Test("Initial state is stable with zero momentum")
    func initialState() {
        let signal = QualitySignal()

        #expect(signal.momentum == 0)
        #expect(signal.trend == .stable)
        #expect(signal.lastState == nil)
    }

    @Test("First nominal reading sets state but not momentum")
    func firstNominalReading() {
        var signal = QualitySignal()

        signal.record(.nominal)

        #expect(signal.lastState == .nominal)
        #expect(signal.momentum == 0)
        #expect(signal.trend == .stable)
    }

    @Test("First non-nominal reading initializes momentum")
    func firstNonNominalReading() {
        var signal = QualitySignal()

        signal.record(.fair)

        #expect(signal.lastState == .fair)
        // Momentum initialized based on absolute thermal level
        // fair = 0.33 normalized, momentum = 0.33 * 0.3 = ~0.099
        #expect(signal.momentum > 0)
        #expect(signal.trend == .stable) // Still in dead zone
    }

    @Test("Heating increases momentum")
    func heating() {
        var signal = QualitySignal()

        signal.record(.nominal)
        signal.record(.fair)
        signal.record(.serious)
        signal.record(.critical)

        #expect(signal.momentum > QualitySignal.deadZone)
        #expect(signal.trend == .heating)
    }

    @Test("Cooling decreases momentum and enters cooling state")
    func cooling() {
        var signal = QualitySignal()

        // To build up strong negative momentum exceeding -0.15 threshold,
        // we need rapid sustained cooling. Start high and drop quickly.
        signal.record(.critical)
        signal.record(.critical)  // Stabilize at critical
        signal.record(.critical)
        signal.record(.serious)   // Step down (-0.33)
        signal.record(.fair)      // Step down (-0.34)
        signal.record(.nominal)   // Step down (-0.33) - should push momentum < -0.15

        #expect(signal.momentum < -QualitySignal.coolingEntryThreshold,
                "Momentum \(signal.momentum) should be below -\(QualitySignal.coolingEntryThreshold)")
        #expect(signal.direction == .cooling,
                "Direction should be cooling after sustained rapid cooling")
    }

    @Test("Stable state has near-zero momentum")
    func stable() {
        var signal = QualitySignal()

        signal.record(.fair)
        signal.record(.fair)
        signal.record(.fair)
        signal.record(.fair)

        #expect(abs(signal.momentum) < QualitySignal.deadZone)
        #expect(signal.trend == .stable)
    }

    @Test("Reset clears all state")
    func reset() {
        var signal = QualitySignal()

        signal.record(.nominal)
        signal.record(.critical)

        signal.reset()

        #expect(signal.momentum == 0)
        #expect(signal.lastState == nil)
        #expect(signal.lastUpdate == nil)
        #expect(signal.trend == .stable)
    }

    @Test("Momentum uses EMA smoothing")
    func emaSmoothing() {
        var signal = QualitySignal()

        // Single jump shouldn't max out momentum
        signal.record(.nominal)
        signal.record(.critical)

        // Momentum should be significant but not 1.0
        #expect(signal.momentum > 0)
        #expect(signal.momentum < 1.0)
    }

    // MARK: - seedFromCurrentState Tests

    @Test("Seed from nominal sets zero momentum")
    func seedFromNominal() {
        var signal = QualitySignal()

        signal.seedFromCurrentState(.nominal)

        #expect(signal.momentum == 0)
        #expect(signal.lastState == .nominal)
        #expect(signal.lastUpdate != nil)
        #expect(signal.trend == .stable)
    }

    @Test("Seed from fair sets proportional momentum")
    func seedFromFair() {
        var signal = QualitySignal()

        signal.seedFromCurrentState(.fair)

        // fair = 0.33 normalized × 0.3 smoothing = ~0.099
        let expectedMomentum: Float = 0.33 * QualitySignal.smoothingFactor
        #expect(signal.momentum == expectedMomentum)
        #expect(signal.lastState == .fair)
        #expect(signal.trend == .stable) // Still in dead zone
    }

    @Test("Seed from serious sets higher momentum")
    func seedFromSerious() {
        var signal = QualitySignal()

        signal.seedFromCurrentState(.serious)

        // serious = 0.67 normalized × 0.3 smoothing = ~0.201
        let expectedMomentum: Float = 0.67 * QualitySignal.smoothingFactor
        #expect(signal.momentum == expectedMomentum)
        #expect(signal.lastState == .serious)
        // 0.201 is above dead zone (0.1) but below heating entry threshold (0.15)
        #expect(signal.trend == .stable)
    }

    @Test("Seed from critical sets highest momentum")
    func seedFromCritical() {
        var signal = QualitySignal()

        signal.seedFromCurrentState(.critical)

        // critical = 1.0 normalized × 0.3 smoothing = 0.3
        let expectedMomentum: Float = 1.0 * QualitySignal.smoothingFactor
        #expect(signal.momentum == expectedMomentum)
        #expect(signal.lastState == .critical)
        // 0.3 is above heating entry threshold (0.15) but initial direction is stable
        // Direction only changes in record(), not on seed
        #expect(signal.trend == .stable)
    }

    @Test("Seed preserves ability to track subsequent changes")
    func seedThenRecord() {
        var signal = QualitySignal()

        // Seed from serious state
        signal.seedFromCurrentState(.serious)
        let initialMomentum = signal.momentum

        // Record heating to critical
        signal.record(.critical)

        // Momentum should increase (positive delta)
        #expect(signal.momentum > initialMomentum)
        #expect(signal.lastState == .critical)
    }

    // MARK: - Proportional Recovery Tests

    @Test("Recovery magnitude starts at zero")
    func recoveryMagnitudeInitial() {
        let signal = QualitySignal()

        #expect(signal.recoveryMagnitude == 0)
        #expect(signal.recoveryScale == 1.0)
    }

    @Test("Recovery magnitude increases during rapid cooling")
    func recoveryMagnitudeRapidCooling() {
        var signal = QualitySignal()

        // Heat up first
        signal.record(.critical)

        // Then rapidly cool
        signal.record(.serious) // Delta: -0.33
        signal.record(.fair)    // Delta: -0.34
        signal.record(.nominal) // Delta: -0.33

        // Recovery magnitude should be significant
        #expect(signal.recoveryMagnitude > 0)
        #expect(signal.recoveryScale > 1.0)
    }

    @Test("Recovery magnitude provides higher scale for rapid cooling")
    func recoveryScaleAcceleratesRecovery() {
        var signal = QualitySignal()

        // Simulate very rapid cooling (critical → nominal with multiple fast steps)
        signal.record(.critical)
        signal.record(.serious)
        signal.record(.fair)
        signal.record(.nominal)
        signal.record(.nominal)

        // Recovery scale should be above baseline
        // EMA smoothing (0.2) makes it build up gradually
        #expect(signal.recoveryScale > 1.0)
        #expect(signal.recoveryScale <= 3.0) // Clamped at 3.0
    }

    @Test("Recovery magnitude decays when not cooling")
    func recoveryMagnitudeDecay() {
        var signal = QualitySignal()

        // Rapid cooling first
        signal.record(.critical)
        signal.record(.nominal)
        let recoveryAfterCooling = signal.recoveryMagnitude

        // Now stable
        signal.record(.nominal)
        signal.record(.nominal)
        signal.record(.nominal)

        // Recovery magnitude should decay
        #expect(signal.recoveryMagnitude < recoveryAfterCooling)
    }

    @Test("Recovery magnitude resets on reset")
    func recoveryMagnitudeResets() {
        var signal = QualitySignal()

        // Build up recovery magnitude
        signal.record(.critical)
        signal.record(.nominal)

        signal.reset()

        #expect(signal.recoveryMagnitude == 0)
        #expect(signal.recoveryScale == 1.0)
    }

    @Test("Recovery magnitude resets on seed")
    func recoveryMagnitudeSeed() {
        var signal = QualitySignal()

        // Build up recovery magnitude
        signal.record(.critical)
        signal.record(.nominal)

        signal.seedFromCurrentState(.serious)

        #expect(signal.recoveryMagnitude == 0)
        #expect(signal.recoveryScale == 1.0)
    }

    // MARK: - Hysteresis Tests

    @Test("Initial direction is stable")
    func hysteresisInitialDirection() {
        let signal = QualitySignal()

        #expect(signal.direction == .stable)
    }

    @Test("Direction requires exceeding entry threshold to commit to heating")
    func hysteresisHeatingEntry() {
        var signal = QualitySignal()

        // Start heating but stay below entry threshold (0.15)
        signal.record(.nominal)
        signal.record(.fair) // Creates ~0.099 momentum (below 0.15)

        #expect(signal.direction == .stable) // Should not enter heating

        // Continue heating past entry threshold
        signal.record(.serious)
        signal.record(.critical)

        #expect(signal.direction == .heating) // Should now be heating
    }

    @Test("Direction requires dropping below exit threshold to leave heating")
    func hysteresisHeatingExit() {
        var signal = QualitySignal()

        // Enter heating state
        signal.record(.nominal)
        signal.record(.serious)
        signal.record(.critical)
        #expect(signal.direction == .heating)

        // Cool slightly but stay above exit threshold (0.05)
        signal.record(.serious) // Momentum still positive
        #expect(signal.direction == .heating) // Should stay heating

        // Cool more to drop below exit threshold
        signal.record(.fair)
        signal.record(.nominal)
        signal.record(.nominal)

        #expect(signal.direction == .stable) // Should exit heating
    }

    @Test("Direction prevents rapid oscillation at thermal boundaries")
    func hysteresisPreventOscillation() {
        var signal = QualitySignal()

        // Get momentum near boundary (~0.12)
        signal.record(.nominal)
        signal.record(.fair)

        let initialDirection = signal.direction

        // Oscillate momentum around boundary
        signal.record(.fair)     // Stable
        signal.record(.serious)  // Heat slightly
        signal.record(.fair)     // Cool slightly
        signal.record(.serious)  // Heat slightly
        signal.record(.fair)     // Cool slightly

        // Direction should remain stable due to hysteresis gap
        #expect(signal.direction == initialDirection)
    }

    @Test("Direction resets to stable on reset")
    func hysteresisResetDirection() {
        var signal = QualitySignal()

        // Enter heating state
        signal.record(.nominal)
        signal.record(.critical)

        signal.reset()

        #expect(signal.direction == .stable)
    }

    @Test("Direction resets to stable on seed")
    func hysteresisSeedDirection() {
        var signal = QualitySignal()

        // Enter heating state
        signal.record(.nominal)
        signal.record(.critical)

        signal.seedFromCurrentState(.serious)

        #expect(signal.direction == .stable)
    }
}
