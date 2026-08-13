//
//  OnAirIndicator.swift
//  WXYC
//
//  Shared pulsing "live" indicator dot for the on-air banner styles.
//
//  Created by Jake Bromberg on 06/19/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI

extension Color {
    /// The shared "on air" live-signal color used across the banner styles.
    static let onAirSignal = Color.green
}

/// A small dot with a soft glow that gently pulses to evoke a live broadcast.
///
/// Shared by the on-air banner styles. Honors Reduce Motion by holding steady.
///
/// ## Keeping the pulse cheap
///
/// This is the only always-running animation on the Now Playing screen, so it
/// alone decides whether the app can go idle: a live SwiftUI animation holds the
/// ViewGraph display link open, and every frame it steps costs a render pass
/// over the whole view tree rather than over this 9pt dot. Two things keep that
/// pass off the CPU, and both are load-bearing:
///
/// - **Only the leaf circle's opacity animates.** `.opacity` and `.animation`
///   sit *inside* `.shadow` so the animated property lands on a plain leaf that
///   Core Animation can drive on its own. Wrapping the animation around the
///   shadow instead makes the item a compositing node, which SwiftUI must
///   re-emit every frame.
/// - **The blur radius is constant.** A blur radius can't be handed off as a
///   detached animation, so animating it forces a per-frame re-render by
///   construction — see ``glowRadius(blurRadius:isPulsing:)``.
struct OnAirIndicator: View {
    var size: CGFloat = 9
    var color: Color = .onAirSignal

    /// Glow blur radius. When `nil`, ``defaultGlowRadius`` is used.
    var blurRadius: CGFloat? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    // MARK: - Pulse Canon

    /// Opacity at the dim end of the pulse.
    static let restingOpacity: Double = 0.65

    /// Opacity at the bright end of the pulse, and the fixed opacity under
    /// Reduce Motion.
    static let peakOpacity: Double = 1.0

    /// Glow blur radius used when the caller doesn't pin one.
    static let defaultGlowRadius: CGFloat = 4.5

    /// One half-cycle of the pulse.
    static let pulseDuration: Double = 1.1

    var body: some View {
        #if canImport(UIKit)
        // CoreAnimation drives the pulse — see ``OnAirPulseView`` for why.
        OnAirPulseView(
            size: size,
            color: color,
            blurRadius: Self.glowRadius(blurRadius: blurRadius, isPulsing: isPulsing),
            reduceMotion: reduceMotion
        )
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        #else
        swiftUIPulse
        #endif
    }

    /// The SwiftUI pulse, used where UIKit isn't available.
    ///
    /// Costs a whole-tree render pass per frame (SwiftUI steps `repeatForever` on
    /// the CPU), which is exactly why the UIKit path exists. Kept so the native
    /// macOS target has something correct to fall back to rather than a dot that
    /// silently stops pulsing.
    private var swiftUIPulse: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(Self.dotOpacity(isPulsing: isPulsing, reduceMotion: reduceMotion))
            .animation(Self.pulseAnimation(reduceMotion: reduceMotion), value: isPulsing)
            .shadow(
                color: color.opacity(0.9),
                radius: Self.glowRadius(blurRadius: blurRadius, isPulsing: isPulsing)
            )
            .onAppear { isPulsing = true }
            .accessibilityHidden(true)
    }

    // MARK: - Pulse Rules

    /// The pulse animation, or `nil` when Reduce Motion is on.
    static func pulseAnimation(reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        return .easeInOut(duration: pulseDuration).repeatForever(autoreverses: true)
    }

    /// The dot's opacity for a pulse phase. The only animated property.
    static func dotOpacity(isPulsing: Bool, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return peakOpacity }
        return isPulsing ? peakOpacity : restingOpacity
    }

    /// The glow's blur radius.
    ///
    /// Takes `isPulsing` and deliberately ignores it: the phase-invariance is
    /// the point, and a test asserts it directly rather than trusting a reader
    /// to notice the absence of a parameter. Animating a blur radius can't be
    /// detached to Core Animation, so a phase-dependent radius would put the
    /// whole view tree back into a per-frame render pass.
    static func glowRadius(blurRadius: CGFloat?, isPulsing: Bool) -> CGFloat {
        blurRadius ?? defaultGlowRadius
    }
}

#Preview {
    OnAirIndicator()
        .padding()
        .background(.black)
}
