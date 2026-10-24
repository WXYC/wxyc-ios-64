//
//  ScrollShadowModifier.swift
//  WXYC
//
//  Moved out of `PlaycutRowView` so any row can lean its artwork's shadow with
//  its position in the playlist's "scroll" coordinate space.
//
//  Created by Jake Bromberg on 10/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Artwork
import SwiftUI

// Preference key to track scroll position
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Tracks the row's position in the scroll view and drives the artwork's shadow
/// offset from it, so the shadow leans with the row as it scrolls. Shared by the
/// plain row and the ticket.
struct ScrollShadowModifier: ViewModifier {
    @Binding var shadowYOffset: CGFloat
    let top: CGFloat
    let bottom: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { scrollProxy in
                    let scrollFrame = scrollProxy.frame(in: .named("scroll"))

                    return Color.clear
                        .preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: scrollFrame.midY
                        )
                }
            )
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { scrollPosition in
                // Normalize the row's midY within the screen (0 at top, 1 at
                // bottom), then interpolate the shadow offset across that range.
                let screenHeight = ArtworkDisplayMetrics.viewportHeight
                let normalizedPosition = min(max(scrollPosition / screenHeight, 0), 1)
                shadowYOffset = top + (normalizedPosition * (bottom - top))
            }
    }
}
