//
//  VisualizerSmoothing.swift
//  PlayerHeaderView
//
//  Frame-rate-independent smoothing for the LCD spectrum analyzer bars. The
//  attack/decay constants were authored against a 60 FPS timeline; these helpers
//  rescale them by elapsed time so the bars look the same at any refresh rate.
//
//  Created by Jake Bromberg on 09/10/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Frame-rate-independent smoothing for the visualizer bars.
///
/// The tuning constants below were chosen by eye against a fixed 60 FPS timeline
/// and were originally applied once per frame. That made every animation's
/// wall-clock duration a function of the refresh rate: on a 120 Hz display the
/// bars decayed twice as fast and the falling dots hit the floor in half a
/// second instead of one. Rescaling by elapsed time decouples the look of the
/// visualizer from how often it happens to be drawn.
enum VisualizerSmoothing {

    /// The frame duration the constants below were authored against.
    static let referenceFrameDuration: Double = 1.0 / 60.0

    /// Longest elapsed time a single step may account for, in seconds.
    ///
    /// Without this, the first frame after a stall (a long main-thread hitch, or
    /// the timeline resuming) would collapse the bars in one step and read as a
    /// visual snap. Clamping spreads the catch-up over the following frames.
    static let maximumElapsed: Double = 1.0 / 15.0

    /// Blend fraction toward the target when a bar is rising, per reference frame.
    ///
    /// Fast attack so beats and peaks are not smoothed away.
    static let attackFactor: Float = 0.5

    /// Fraction of the current value retained when a bar is falling, per reference frame.
    ///
    /// Slow decay so the falloff reads as smooth rather than jittery.
    static let decayFactor: Float = 0.85

    /// Fraction retained by a falling dot per reference frame.
    ///
    /// Tuned for roughly a one-second fall to the floor once playback stops.
    static let fallDecayFactor: Float = 0.92

    /// Rescales a per-reference-frame retention factor to an arbitrary elapsed time.
    ///
    /// A retention factor `r` applied once per 1/60 s compounds to `r^(elapsed * 60)`
    /// over `elapsed` seconds, which is what this returns. At exactly
    /// ``referenceFrameDuration`` the authored constant passes through unchanged.
    ///
    /// - Parameters:
    ///   - perFrame: The retained fraction per reference frame, in 0...1.
    ///   - elapsed: Seconds since the previous step. Negative values are treated
    ///     as zero and long stalls are clamped to ``maximumElapsed``.
    /// - Returns: The fraction retained across `elapsed` seconds.
    static func retention(perFrame: Float, elapsed: Double) -> Float {
        guard perFrame > 0 else { return 0 }
        guard perFrame < 1 else { return 1 }
        let clampedElapsed = min(max(elapsed, 0), maximumElapsed)
        let frames = clampedElapsed / referenceFrameDuration
        return Float(pow(Double(perFrame), frames))
    }

    /// Advances a bar toward its target using asymmetric attack/decay smoothing.
    ///
    /// - Parameters:
    ///   - current: The bar's current smoothed value.
    ///   - target: The value the audio data wants the bar to show.
    ///   - elapsed: Seconds since the previous frame.
    /// - Returns: The new smoothed value.
    static func smooth(current: Float, target: Float, elapsed: Double) -> Float {
        if target > current {
            // Rising: fast attack to catch beats and peaks.
            let remaining = retention(perFrame: 1 - attackFactor, elapsed: elapsed)
            return target - (target - current) * remaining
        } else {
            // Falling: smooth decay for visual appeal.
            let retained = retention(perFrame: decayFactor, elapsed: elapsed)
            return current * retained + target * (1 - retained)
        }
    }

    /// Decays a falling dot toward the floor.
    ///
    /// - Parameters:
    ///   - value: The dot's current height.
    ///   - elapsed: Seconds since the previous frame.
    /// - Returns: The dot's new height.
    static func decayedDot(_ value: Float, elapsed: Double) -> Float {
        value * retention(perFrame: fallDecayFactor, elapsed: elapsed)
    }
}
