import Foundation
import Testing
@testable import Wallpaper

@Suite("ThermalSignal")
struct ThermalSignalTests {

    @Test("Initial state is stable with zero momentum")
    func initialState() {
        let signal = ThermalSignal()

        #expect(signal.momentum == 0)
        #expect(signal.trend == .stable)
        #expect(signal.lastState == nil)
    }

    @Test("First nominal reading sets state but not momentum")
    func firstNominalReading() {
        var signal = ThermalSignal()

        signal.record(.nominal)

        #expect(signal.lastState == .nominal)
        #expect(signal.momentum == 0)
        #expect(signal.trend == .stable)
    }

    @Test("First non-nominal reading initializes momentum")
    func firstNonNominalReading() {
        var signal = ThermalSignal()

        signal.record(.fair)

        #expect(signal.lastState == .fair)
        // Momentum initialized based on absolute thermal level
        // fair = 0.33 normalized, momentum = 0.33 * 0.3 = ~0.099
        #expect(signal.momentum > 0)
        #expect(signal.trend == .stable) // Still in dead zone
    }

    @Test("Heating increases momentum")
    func heating() {
        var signal = ThermalSignal()

        signal.record(.nominal)
        signal.record(.fair)
        signal.record(.serious)
        signal.record(.critical)

        #expect(signal.momentum > ThermalSignal.deadZone)
        #expect(signal.trend == .heating)
    }

    @Test("Cooling decreases momentum")
    func cooling() {
        var signal = ThermalSignal()

        signal.record(.critical)
        signal.record(.serious)
        signal.record(.fair)
        signal.record(.nominal)

        #expect(signal.momentum < -ThermalSignal.deadZone)
        #expect(signal.trend == .cooling)
    }

    @Test("Stable state has near-zero momentum")
    func stable() {
        var signal = ThermalSignal()

        signal.record(.fair)
        signal.record(.fair)
        signal.record(.fair)
        signal.record(.fair)

        #expect(abs(signal.momentum) < ThermalSignal.deadZone)
        #expect(signal.trend == .stable)
    }

    @Test("Reset clears all state")
    func reset() {
        var signal = ThermalSignal()

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
        var signal = ThermalSignal()

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
        var signal = ThermalSignal()

        signal.seedFromCurrentState(.nominal)

        #expect(signal.momentum == 0)
        #expect(signal.lastState == .nominal)
        #expect(signal.lastUpdate != nil)
        #expect(signal.trend == .stable)
    }

    @Test("Seed from fair sets proportional momentum")
    func seedFromFair() {
        var signal = ThermalSignal()

        signal.seedFromCurrentState(.fair)

        // fair = 0.33 normalized × 0.3 smoothing = ~0.099
        let expectedMomentum: Float = 0.33 * ThermalSignal.smoothingFactor
        #expect(signal.momentum == expectedMomentum)
        #expect(signal.lastState == .fair)
        #expect(signal.trend == .stable) // Still in dead zone
    }

    @Test("Seed from serious sets higher momentum")
    func seedFromSerious() {
        var signal = ThermalSignal()

        signal.seedFromCurrentState(.serious)

        // serious = 0.67 normalized × 0.3 smoothing = ~0.201
        let expectedMomentum: Float = 0.67 * ThermalSignal.smoothingFactor
        #expect(signal.momentum == expectedMomentum)
        #expect(signal.lastState == .serious)
        #expect(signal.trend == .heating) // Above dead zone
    }

    @Test("Seed from critical sets highest momentum")
    func seedFromCritical() {
        var signal = ThermalSignal()

        signal.seedFromCurrentState(.critical)

        // critical = 1.0 normalized × 0.3 smoothing = 0.3
        let expectedMomentum: Float = 1.0 * ThermalSignal.smoothingFactor
        #expect(signal.momentum == expectedMomentum)
        #expect(signal.lastState == .critical)
        #expect(signal.trend == .heating)
    }

    @Test("Seed preserves ability to track subsequent changes")
    func seedThenRecord() {
        var signal = ThermalSignal()

        // Seed from serious state
        signal.seedFromCurrentState(.serious)
        let initialMomentum = signal.momentum

        // Record heating to critical
        signal.record(.critical)

        // Momentum should increase (positive delta)
        #expect(signal.momentum > initialMomentum)
        #expect(signal.lastState == .critical)
    }
}
