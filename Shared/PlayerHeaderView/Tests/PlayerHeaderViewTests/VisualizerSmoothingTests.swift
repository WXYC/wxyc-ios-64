//
//  VisualizerSmoothingTests.swift
//  PlayerHeaderView
//
//  Tests that the spectrum analyzer's attack/decay smoothing depends on elapsed
//  time rather than on how often it happens to be called.
//
//  Created by Jake Bromberg on 09/10/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import PlayerHeaderView

@Suite("Visualizer smoothing")
struct VisualizerSmoothingTests {

    /// The bars must decay by the same amount over the same wall-clock span
    /// whether the timeline is ticking at 60 or 120 FPS. Applied once per frame,
    /// as the view used to, doubling the frame rate halved every decay time.
    @Test("One second of decay lands in the same place at 60 and 120 FPS")
    func decayIsFrameRateIndependent() {
        func decayOverOneSecond(fps: Double) -> Float {
            var value: Float = 64
            for _ in 0..<Int(fps) {
                value = VisualizerSmoothing.smooth(current: value, target: 0, elapsed: 1.0 / fps)
            }
            return value
        }

        #expect(abs(decayOverOneSecond(fps: 60) - decayOverOneSecond(fps: 120)) < 0.01)
    }

    @Test("Falling dots reach the floor in the same time at 60 and 120 FPS")
    func fallingDotsAreFrameRateIndependent() {
        func secondsToFall(fps: Double) -> Double {
            var value: Float = 64
            var frames = 0
            while value > 0.5 && frames < Int(fps) * 10 {
                value = VisualizerSmoothing.decayedDot(value, elapsed: 1.0 / fps)
                frames += 1
            }
            return Double(frames) / fps
        }

        #expect(abs(secondsToFall(fps: 60) - secondsToFall(fps: 120)) < 0.05)
    }

    @Test("Attack still reaches the target quickly at 120 FPS")
    func attackRisesTowardTarget() {
        var value: Float = 0
        for _ in 0..<8 {
            value = VisualizerSmoothing.smooth(current: value, target: 64, elapsed: 1.0 / 120.0)
        }
        #expect(value > 48)
        #expect(value <= 64)
    }

    /// Non-vacuity guard: the two frame-rate-independence tests above must be
    /// able to fail. Applying the authored constant once per frame — what the
    /// view did before this change — has to diverge between 60 and 120 FPS, or
    /// those assertions prove nothing.
    @Test("The old per-frame decay really does diverge at 120 FPS")
    func perFrameDecayDivergesAcrossFrameRates() {
        func decayOverOneSecond(fps: Int) -> Float {
            var value: Float = 64
            for _ in 0..<fps {
                value *= VisualizerSmoothing.decayFactor
            }
            return value
        }

        #expect(decayOverOneSecond(fps: 60) > decayOverOneSecond(fps: 120) * 100)
    }

    @Test("At the reference frame duration the authored constant is unchanged")
    func referenceFrameMatchesAuthoredConstant() {
        let retained = VisualizerSmoothing.retention(
            perFrame: VisualizerSmoothing.decayFactor,
            elapsed: VisualizerSmoothing.referenceFrameDuration
        )
        #expect(abs(retained - VisualizerSmoothing.decayFactor) < 1e-5)
    }

    @Test("A stalled frame cannot decay past the floor")
    func longStallClampsElapsed() {
        let value = VisualizerSmoothing.smooth(current: 64, target: 0, elapsed: 30)
        #expect(value >= 0)
        #expect(value.isFinite)
    }
}
