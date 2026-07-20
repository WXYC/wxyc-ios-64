//
//  HapticEventSpec.swift
//  WXYC
//
//  An engine-free description of the haptic burst the like celebration plays.
//  Kept separate from CoreHaptics playback so the burst math (count, timing,
//  intensity/sharpness clamping) is unit-testable without haptics hardware, and
//  so `LikeHapticSettings` and the DEBUG tuning panel can preview the exact
//  pattern the vendored spray fires.
//
//  Created by Jake Bromberg on 07/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
#if os(iOS)
import CoreHaptics
#endif

/// One haptic event in a like-celebration burst.
struct HapticEventSpec: Equatable, Sendable {
    /// Whether an event is a single tap or a sustained buzz.
    enum Kind: Sendable, CaseIterable, Hashable {
        /// A single punchy tap (`CHHapticEvent` `.hapticTransient`).
        case transient
        /// A sustained buzz of `duration` seconds (`.hapticContinuous`).
        case continuous
    }

    var kind: Kind
    /// Offset from the start of the burst, in seconds.
    var relativeTime: TimeInterval
    /// Strength, 0...1.
    var intensity: Float
    /// Dull thud (0) to crisp click (1).
    var sharpness: Float
    /// Sustain for `.continuous`; 0 (ignored) for `.transient`.
    var duration: TimeInterval

    /// Builds an evenly-spaced burst of `count` identical events. Pure and
    /// deterministic — the testable seam. `intensity`/`sharpness` clamp to
    /// 0...1 and `count` is floored at 1.
    static func burst(
        kind: Kind,
        count: Int,
        intensity: Double,
        sharpness: Double,
        spacing: TimeInterval,
        duration: TimeInterval
    ) -> [HapticEventSpec] {
        let n = max(1, count)
        let clampedIntensity = Float(min(max(intensity, 0), 1))
        let clampedSharpness = Float(min(max(sharpness, 0), 1))
        return (0 ..< n).map { i in
            HapticEventSpec(
                kind: kind,
                relativeTime: TimeInterval(i) * spacing,
                intensity: clampedIntensity,
                sharpness: clampedSharpness,
                duration: kind == .transient ? 0 : duration
            )
        }
    }
}

#if os(iOS)
extension HapticEventSpec {
    /// The CoreHaptics event this spec plays.
    var event: CHHapticEvent {
        let parameters = [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
        ]
        switch kind {
        case .transient:
            return CHHapticEvent(eventType: .hapticTransient, parameters: parameters, relativeTime: relativeTime)
        case .continuous:
            return CHHapticEvent(
                eventType: .hapticContinuous, parameters: parameters, relativeTime: relativeTime, duration: duration
            )
        }
    }

    /// Assembles a playable pattern from a burst, or `nil` if the events are
    /// invalid (e.g. empty).
    static func pattern(from specs: [HapticEventSpec]) -> CHHapticPattern? {
        try? CHHapticPattern(events: specs.map(\.event), parameterCurves: [])
    }
}
#endif
