//
//  OnAirIndicatorTests.swift
//  WXYC
//
//  Tests over the live-dot's pulse constants and the two rules that keep it
//  cheap. The dot's `repeatForever` animation is the only thing on the Now
//  Playing screen that runs while the app is otherwise idle, so it holds
//  SwiftUI's ViewGraph display link open for the whole session — every frame it
//  animates costs a render pass over the entire view tree, not just the 9pt dot.
//
//  Two rules follow, and both are asserted here:
//
//  1. Reduce Motion yields no animation at all — the pulse is decorative.
//  2. The glow's blur radius never varies with the pulse phase. A blur radius
//     cannot be handed to Core Animation as a detached animation, so animating
//     it forces SwiftUI to re-emit the display-list item every frame by
//     construction. Only the leaf circle's opacity animates.
//
//  The rendered cost itself isn't unit-testable; it was verified by sampling the
//  running app before and after. These tests pin the invariants that make the
//  cheap path the only path.
//
//  Created by Jake Bromberg on 08/12/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import SwiftUI
@testable import WXYC

@Suite("OnAirIndicator")
struct OnAirIndicatorTests {
    @Test("Reduce Motion suppresses the pulse animation")
    func reduceMotionSuppressesAnimation() {
        #expect(OnAirIndicator.pulseAnimation(reduceMotion: true) == nil)
    }

    @Test("motion allowed yields a pulse animation")
    func motionAllowedAnimates() {
        #expect(OnAirIndicator.pulseAnimation(reduceMotion: false) != nil)
    }

    /// `arguments:` is evaluated off the main actor while this target builds with
    /// `-default-isolation=MainActor`, so the expectations are named by a plain
    /// `Bool` here and resolved to `OnAirIndicator`'s constants inside the body.
    @Test("the pulse moves opacity between its two endpoints", arguments: [true, false])
    func opacityEndpoints(isPulsing: Bool) {
        let expected = isPulsing ? OnAirIndicator.peakOpacity : OnAirIndicator.restingOpacity

        #expect(
            OnAirIndicator.dotOpacity(isPulsing: isPulsing, reduceMotion: false) == expected
        )
    }

    @Test("the two opacity endpoints actually differ")
    func opacityEndpointsDiffer() {
        #expect(OnAirIndicator.restingOpacity < OnAirIndicator.peakOpacity)
    }

    @Test("Reduce Motion pins opacity fully on", arguments: [true, false])
    func reduceMotionPinsOpacity(isPulsing: Bool) {
        #expect(
            OnAirIndicator.dotOpacity(isPulsing: isPulsing, reduceMotion: true)
                == OnAirIndicator.peakOpacity
        )
    }

    /// The load-bearing one: whatever else changes, the blur radius must not
    /// depend on the pulse phase. If this fails, the dot is re-rendering the
    /// whole display-list item 60 times a second again.
    @Test("the glow radius never varies with the pulse phase", arguments: [
        Optional<CGFloat>.none,
        .some(4.5),
        .some(12),
    ])
    func glowRadiusIsPhaseInvariant(blurRadius: CGFloat?) {
        let pulsing = OnAirIndicator.glowRadius(blurRadius: blurRadius, isPulsing: true)
        let resting = OnAirIndicator.glowRadius(blurRadius: blurRadius, isPulsing: false)

        #expect(pulsing == resting)
    }

    @Test("an explicit blur radius wins over the default")
    func explicitBlurRadiusWins() {
        #expect(OnAirIndicator.glowRadius(blurRadius: 12, isPulsing: true) == 12)
        #expect(
            OnAirIndicator.glowRadius(blurRadius: nil, isPulsing: true)
                == OnAirIndicator.defaultGlowRadius
        )
    }
}
