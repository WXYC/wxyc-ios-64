//
//  DetailPresentation.swift
//  WXYC
//
//  Presentation chrome shared by the app's full-screen detail covers — the On
//  Tour `ConcertDetailView` and the flowsheet `PlaycutDetailView` — so both read
//  as the same kind of "moment": a solid dark backdrop that the tapped row zooms
//  into (`.navigationTransition(.zoom)`), fronted by a matching frosted-circle
//  chrome button. Keeping the backdrop color and the glyph treatment in one place
//  means the two covers can't drift apart.
//
//  Created by Jake Bromberg on 08/01/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI

/// Shared look for the app's full-screen detail covers.
enum DetailPresentation {
    /// The opaque dark backdrop the covers sit over, so they read as a "moment"
    /// rather than the app's translucent wallpaper surface.
    static let backdrop = Color(red: 0.063, green: 0.055, blue: 0.102)

    /// The frosted-circle treatment shared by the covers' chrome buttons (back /
    /// close, share, add-to-calendar).
    @ViewBuilder
    static func chromeGlyph(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(.ultraThinMaterial, in: .circle)
            .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
    }
}
