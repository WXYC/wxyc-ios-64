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
struct OnAirIndicator: View {
    var size: CGFloat = 9
    var color: Color = .onAirSignal

    /// Fixed glow blur radius. When `nil`, the glow pulses on its own schedule.
    var blurRadius: CGFloat? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.9), radius: glowRadius)
            .opacity(dotOpacity)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
            .accessibilityHidden(true)
    }

    private var glowRadius: CGFloat {
        if let blurRadius { return blurRadius }
        return reduceMotion ? 3 : (isPulsing ? 6 : 2)
    }

    private var dotOpacity: Double {
        reduceMotion ? 1 : (isPulsing ? 1 : 0.65)
    }
}

#Preview {
    OnAirIndicator()
        .padding()
        .background(.black)
}
