//
//  PlaceholderArtworkView.swift
//  WXUI
//
//  Placeholder view shown while artwork loads.
//
//  Created by Jake Bromberg on 11/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI

/// Placeholder view with WXYC logo and animated gradient background.
public struct PlaceholderArtworkView: View {
    let cornerRadius: CGFloat
    let meshGradient: AnimatedMeshGradient
    /// Whether the placeholder draws itself in glass. The detail-card header keeps
    /// the glass treatment; the row placeholder opts out (`glass: false`) so the
    /// artwork column reads flat, matching the loaded/loading thumbnails there.
    let glass: Bool

    public init(
        cornerRadius: CGFloat = 12,
        meshGradient: AnimatedMeshGradient = AnimatedMeshGradient(),
        glass: Bool = true
    ) {
        self.cornerRadius = cornerRadius
        self.meshGradient = meshGradient
        self.glass = glass
    }

    private var tint: Color {
        Color(hue: 248 / 360, saturation: 1, brightness: 1, opacity: 0.25)
    }

    private var backdropShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .circular)
    }

    @ViewBuilder private var backdrop: some View {
        if glass {
            backdropShape.glassEffectClearTintedInteractiveIfAvailable(tint: tint, in: backdropShape)
        } else {
            backdropShape.fill(tint)
        }
    }

    @ViewBuilder private var logo: some View {
        if glass {
            WXYCLogo().glassEffectClearIfAvailable(in: WXYCLogoShape())
        } else {
            WXYCLogo()
        }
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                backdrop
                    .frame(width: geometry.size.width * 0.8, height: geometry.size.width * 0.8)
                    .opacity(0.65)
                    .clipShape(backdropShape)

                logo
                    .background(meshGradient.opacity(0.6))
                    .clipShape(WXYCLogoShape())
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .backgroundStyle(.clear)
    }
}
