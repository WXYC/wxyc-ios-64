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

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(Capsule().fill(.white.opacity(Self.fillOpacity)))
            .overlay(Capsule().stroke(.white.opacity(Self.strokeOpacity), lineWidth: Self.strokeWidth))
    }
}

public extension ButtonStyle where Self == GlassChipButtonStyle {
    /// The canon glass capsule chip style. See ``GlassChipButtonStyle``.
    static var glassChip: GlassChipButtonStyle { GlassChipButtonStyle() }
}
