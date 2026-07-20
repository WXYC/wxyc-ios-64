//
//  HapticEventSpecTests.swift
//  WXYC
//
//  Guards the pure haptic-burst shaping behind the like celebration: how the
//  tunable settings (count, spacing, intensity, sharpness, event kind) become an
//  evenly-spaced list of events, independent of CoreHaptics playback.
//
//  Created by Jake Bromberg on 07/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import WXYC

@Suite("Haptic burst shaping")
struct HapticEventSpecTests {
    @Test("Count sets the number of events")
    func countSetsEventNumber() {
        let specs = HapticEventSpec.burst(
            kind: .transient, count: 4, intensity: 0.5, sharpness: 0.5, spacing: 0.03, duration: 0.05
        )
        #expect(specs.count == 4)
    }

    @Test("Count floors at one")
    func countFloorsAtOne() {
        let specs = HapticEventSpec.burst(
            kind: .transient, count: 0, intensity: 0.5, sharpness: 0.5, spacing: 0.03, duration: 0.05
        )
        #expect(specs.count == 1)
    }

    @Test("Intensity and sharpness clamp to 0...1")
    func clampsStrength() {
        let hot = HapticEventSpec.burst(
            kind: .transient, count: 1, intensity: 5, sharpness: 5, spacing: 0.03, duration: 0.05
        )
        #expect(hot.first?.intensity == 1)
        #expect(hot.first?.sharpness == 1)

        let cold = HapticEventSpec.burst(
            kind: .transient, count: 1, intensity: -5, sharpness: -5, spacing: 0.03, duration: 0.05
        )
        #expect(cold.first?.intensity == 0)
        #expect(cold.first?.sharpness == 0)
    }

    @Test("Events are evenly spaced from zero")
    func evenSpacing() {
        let specs = HapticEventSpec.burst(
            kind: .transient, count: 3, intensity: 0.5, sharpness: 0.5, spacing: 0.02, duration: 0.05
        )
        #expect(specs[0].relativeTime == 0)
        #expect(abs(specs[1].relativeTime - 0.02) < 1e-9)
        #expect(abs(specs[2].relativeTime - 0.04) < 1e-9)
    }

    @Test("Transient events carry no duration")
    func transientNoDuration() {
        let specs = HapticEventSpec.burst(
            kind: .transient, count: 2, intensity: 0.5, sharpness: 0.5, spacing: 0.02, duration: 0.05
        )
        #expect(specs.allSatisfy { $0.duration == 0 })
    }

    @Test("Continuous events keep their duration")
    func continuousKeepsDuration() {
        let specs = HapticEventSpec.burst(
            kind: .continuous, count: 2, intensity: 0.5, sharpness: 0.5, spacing: 0.02, duration: 0.05
        )
        #expect(specs.allSatisfy { $0.duration == 0.05 })
    }

    #if os(iOS)
    @Test("A valid burst produces a playable pattern")
    func buildsPattern() {
        let specs = HapticEventSpec.burst(
            kind: .transient, count: 3, intensity: 0.8, sharpness: 0.6, spacing: 0.03, duration: 0.05
        )
        #expect(HapticEventSpec.pattern(from: specs) != nil)
    }
    #endif
}
