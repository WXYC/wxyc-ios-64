//
//  PlaceholderArtworkView.swift
//  WXUI
//
//  Created by Jake Bromberg on 11/26/25.
//

import SwiftUI

/// Placeholder view with WXYC logo and animated gradient background.
public struct PlaceholderArtworkView: View {
    let cornerRadius: CGFloat
    let shadowYOffset: CGFloat
    let meshGradient: AnimatedMeshGradient

    public init(
        cornerRadius: CGFloat = 12,
        shadowYOffset: CGFloat = 0,
        meshGradient: AnimatedMeshGradient = AnimatedMeshGradient()
    ) {
        self.cornerRadius = cornerRadius
        self.shadowYOffset = shadowYOffset
        self.meshGradient = meshGradient
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .circular)
                    .glassEffectClearTintedInteractiveIfAvailable(
                        tint: Color(
                            hue: 248 / 360,
                            saturation: 100 / 100,
                            brightness: 100 / 100,
                            opacity: 0.25
                        ),
                        in: RoundedRectangle(
                            cornerRadius: cornerRadius,
                            style: .circular
                        )
                    )
                    .frame(width: geometry.size.width * 0.8, height: geometry.size.width * 0.8)
                    .opacity(0.65)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: cornerRadius,
                            style: .circular
                        )
                    )
                    .shadow(radius: 2, x: 0, y: shadowYOffset)

                WXYCLogo()
                    .glassEffectClearIfAvailable(in: WXYCLogoShape())
                    .background(
                        meshGradient.opacity(0.6)
                    )
                    .clipShape(WXYCLogoShape())
                    .shadow(radius: 2, x: 0, y: shadowYOffset)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .backgroundStyle(.clear)
    }
}
