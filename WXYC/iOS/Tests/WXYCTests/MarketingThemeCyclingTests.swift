//
//  MarketingThemeCyclingTests.swift
//  WXYC
//
//  Verifies the `-marketing` recording's theme-cycling loop guarantees a
//  minimum swap count regardless of individual cycle timing. A single cycle
//  whose randomly-picked theme is several carousel steps away can itself take
//  close to (or past) `minimumDuration`, which — checked alone — would
//  collapse the "signature visual" scene to one swap instead of the "1–2
//  swaps" the storyboard documents. `shouldContinueThemeCycling` is the pure
//  decision factored out of the loop so this is testable without a real
//  `ContinuousClock`.
//
//  Created by Jake Bromberg on 07/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import WXYC

@Suite("Marketing mode theme-cycling loop")
struct MarketingThemeCyclingTests {
    @Test("Continues below the minimum cycle count even once the duration has elapsed")
    func continuesBelowMinimumCycleCount() {
        let shouldContinue = MarketingModeController.shouldContinueThemeCycling(
            cycleCount: 1,
            elapsed: .seconds(7),
            minimumCycleCount: 2,
            minimumDuration: .seconds(6)
        )
        #expect(shouldContinue)
    }

    @Test("Continues below the minimum duration even once the cycle count is met")
    func continuesBelowMinimumDuration() {
        let shouldContinue = MarketingModeController.shouldContinueThemeCycling(
            cycleCount: 2,
            elapsed: .seconds(3),
            minimumCycleCount: 2,
            minimumDuration: .seconds(6)
        )
        #expect(shouldContinue)
    }

    @Test("Stops once both the minimum cycle count and duration are met")
    func stopsOnceBothFloorsAreMet() {
        let shouldContinue = MarketingModeController.shouldContinueThemeCycling(
            cycleCount: 2,
            elapsed: .seconds(8),
            minimumCycleCount: 2,
            minimumDuration: .seconds(6)
        )
        #expect(!shouldContinue)
    }
}
