//
//  LikeHapticSettings.swift
//  WXYC
//
//  The tunable shape of the like celebration: how hard the haptic hits, and how
//  many hearts spray how far. The vendored spray reads `shared` at fire time;
//  the DEBUG tuning panel (opened from the Liked header) writes to it and
//  previews every change. The defaults are the shipping values, so release
//  builds get the tuned feel without the panel.
//
//  Created by Jake Bromberg on 07/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

@MainActor
@Observable
final class LikeHapticSettings {
    /// The one instance the spray reads and the tuning panel writes.
    static let shared = LikeHapticSettings()

    // MARK: - Haptics

    /// Single crisp taps (`.transient`) hit harder than a sustained buzz.
    var kind: HapticEventSpec.Kind = .transient
    /// Peak strength, 0...1. The stock Pow spray peaked near 0.48; tuned to full.
    var intensity: Double = 1.0
    /// Dull thud (0) to crisp click (1). Stock spray was a dull 0.2.
    var sharpness: Double = 0.5
    /// Number of taps in the burst. Stored as a `Double` for slider binding.
    var eventCount: Double = 1
    /// Seconds between taps.
    var spacing: Double = 0.03
    /// Sustain per tap for `.continuous`; ignored for `.transient`.
    var duration: Double = 0.05

    // MARK: - Particles

    /// Hearts drawn per burst. Stored as a `Double` for slider binding; the
    /// stock spray drew 11, which felt like too many.
    var particleCount: Double = 6
    /// Multiplier on how far particles travel from the origin. 1 = stock Pow.
    var travel: Double = 0.72

    /// The haptic burst these settings describe.
    func makeEvents() -> [HapticEventSpec] {
        HapticEventSpec.burst(
            kind: kind,
            count: Int(eventCount.rounded()),
            intensity: intensity,
            sharpness: sharpness,
            spacing: spacing,
            duration: duration
        )
    }

    /// Particle count rounded and clamped to the spray's 1...16 SIMD fan width.
    var resolvedParticleCount: Int {
        min(max(Int(particleCount.rounded()), 1), 16)
    }
}
