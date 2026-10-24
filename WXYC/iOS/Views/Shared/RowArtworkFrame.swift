//
//  RowArtworkFrame.swift
//  WXYC
//
//  The frame a song row draws its artwork in: clipped to `ArtworkStyle`'s
//  rounded rectangle, a clear glass effect, and a soft shadow that leans with
//  the row's scroll position. `LoadedArtworkView` and `LoadingArtworkView` use
//  it for album art; `SpecialtyCardView` uses it for a program's logo, so the
//  two cards' artwork carries the same treatment without a second copy of it.
//
//  Created by Jake Bromberg on 10/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI
import WXUI

/// Glass effect and shadow for row artwork.
private struct ArtworkShadowModifier: ViewModifier {
    let shadowRadius: CGFloat
    let shadowYOffset: CGFloat

    func body(content: Content) -> some View {
        content
            .glassEffectClearIfAvailable(in: ArtworkStyle.roundedRectangle)
            .shadow(radius: shadowRadius, x: 0, y: shadowYOffset)
    }
}

extension View {
    func artworkShadow(radius: CGFloat, yOffset: CGFloat) -> some View {
        modifier(ArtworkShadowModifier(shadowRadius: radius, shadowYOffset: yOffset))
    }
}

/// Any artwork content, clipped, glassed, shadowed and centered the way a song
/// row's album art is.
struct RowArtworkFrame<Content: View>: View {
    let shadowYOffset: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .clipShape(ArtworkStyle.roundedRectangle)
            .artworkShadow(radius: 3, yOffset: shadowYOffset)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
