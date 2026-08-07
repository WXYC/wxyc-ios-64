//
//  GlassChipButtonStyle.swift
//  WXUI
//
//  The glass capsule chip duplicated across three On Tour buttons — a filter
//  pill, the "Filter" button, and the concert detail's "Directions" button:
//  white text over `Capsule().fill(.white.opacity(0.16))` with a ~0.25-opacity
//  stroke, each hand-copied and each independently applying `.buttonStyle(.plain)`
//  on top. The three strokes had already drifted to 0.25/0.25/0.22 by the time
//  this was extracted — adopting one style pins all three back to 0.25.
//
//  Created by Jake Bromberg on 08/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI

/// A `ButtonStyle` for a glass capsule chip: white foreground over a translucent
/// white capsule fill with a hairline stroke. Replaces `.buttonStyle(.plain)`
/// plus a hand-copied `.foregroundStyle`/`.background`/`.overlay` trio — apply
/// `.buttonStyle(.glassChip)` and keep only the label's own padding at the call
/// site.
public struct GlassChipButtonStyle: ButtonStyle {
    /// The capsule fill's opacity, over `.white`. Canon: 0.16.
    public static var fillOpacity: Double { 0.16 }
    /// The capsule stroke's opacity, over `.white`. Canon: 0.25.
    public static var strokeOpacity: Double { 0.25 }
    /// The capsule stroke's line width. Canon: 1pt.
    public static var strokeWidth: CGFloat { 1 }
    /// The label's opacity while the chip is held down. Canon: 0.7.
    public static var pressedOpacity: Double { 0.7 }

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .opacity(Self.labelOpacity(isPressed: configuration.isPressed))
            .background(Capsule().fill(.white.opacity(Self.fillOpacity)))
            .overlay(Capsule().stroke(.white.opacity(Self.strokeOpacity), lineWidth: Self.strokeWidth))
    }

    /// The label's opacity for a given press state. Exposed as a pure function
    /// (rather than inlined in `makeBody`) so the branch is directly testable —
    /// the rendered view isn't inspectable without a snapshot dependency this
    /// package deliberately doesn't take on.
    ///
    /// A custom `ButtonStyle` gets no press feedback for free: the moment these
    /// three buttons stopped being `.buttonStyle(.plain)`, whatever dimming they
    /// had became this style's job. Without it, tapping "Filter" on the On Tour
    /// tab acknowledges nothing until the sheet animates in.
    static func labelOpacity(isPressed: Bool) -> Double {
        isPressed ? pressedOpacity : 1
    }
}

public extension ButtonStyle where Self == GlassChipButtonStyle {
    /// The canon glass capsule chip style. See ``GlassChipButtonStyle``.
    static var glassChip: GlassChipButtonStyle { GlassChipButtonStyle() }
}
