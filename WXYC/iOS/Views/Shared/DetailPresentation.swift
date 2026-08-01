//
//  DetailPresentation.swift
//  WXYC
//
//  Presentation chrome shared by the app's full-screen detail covers — the On
//  Tour `ConcertDetailView` and the flowsheet `PlaycutDetailView` — so both read
//  as the same kind of "moment": a frosted backdrop over the app wallpaper that
//  the tapped row zooms into (`.navigationTransition(.zoom)`), fronted by a
//  matching frosted-circle chrome button. Keeping the backdrop and the glyph
//  treatment in one place means the two covers can't drift apart.
//
//  Created by Jake Bromberg on 08/01/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI
import WXUI

/// Shared look for the app's full-screen detail covers.
enum DetailPresentation {
    /// Brightness applied to the frosted material. `0` is the plain
    /// `.ultraThinMaterial` the playcut overlay sheet originally used; that sheet
    /// later shipped `-0.24`. Tuned to `-0.15` to sit between the two.
    private static let materialBrightness = -0.15

    /// The shared backdrop the covers sit over: the app gradient behind a
    /// translucent `.ultraThinMaterial`, so the tapped row zooms into a frosted,
    /// wallpaper-showing surface. Both `PlaycutDetailView` and `ConcertDetailView`
    /// use this, so the two covers can't drift apart.
    static var backdrop: some View {
        ZStack {
            Rectangle().fill(WXYCBackground())
            Rectangle().fill(.ultraThinMaterial).brightness(materialBrightness)
        }
    }

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
