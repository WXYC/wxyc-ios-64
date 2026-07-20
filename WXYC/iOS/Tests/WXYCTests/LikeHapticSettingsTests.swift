//
//  LikeHapticSettingsTests.swift
//  WXYC
//
//  Guards the `resolvedParticleCount` clamp. The spray draws a `particleCount`-
//  wide window of a `SIMD16<Float>` fan, so a count outside 1...16 would subscript
//  out of bounds — this clamp is the sole guard, and this test pins it down.
//
//  Created by Jake Bromberg on 07/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import WXYC

@MainActor
@Suite("LikeHapticSettings particle clamp")
struct LikeHapticSettingsTests {
    @Test(
        "resolvedParticleCount clamps into the spray's 1...16 SIMD fan",
        arguments: [
            (input: 20.0, expected: 16),  // above the fan width -> upper bound
            (input: 16.5, expected: 16),  // rounds up past 16 -> upper bound
            (input: 16.0, expected: 16),  // exact upper bound
            (input: 6.0, expected: 6),    // shipping default, untouched
            (input: 1.0, expected: 1),    // exact lower bound
            (input: 0.4, expected: 1),    // rounds to 0 -> lower bound
            (input: 0.0, expected: 1),    // lower bound
            (input: -5.0, expected: 1),   // below zero -> lower bound
        ] as [(input: Double, expected: Int)]
    )
    func resolvedParticleCountClamps(_ testCase: (input: Double, expected: Int)) {
        let settings = LikeHapticSettings()
        settings.particleCount = testCase.input
        #expect(settings.resolvedParticleCount == testCase.expected)
    }
}
