//
//  PlaceholderArtworkView.swift
//  WXUI
//
//  Created by Jake Bromberg on 11/26/25.
//

import SwiftUI

private struct LogoWidthPreferenceKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue()
    }
}

/// Placeholder view with WXYC logo and optional animated gradient
public struct PlaceholderArtworkView: View {
    let cornerRadius: CGFloat
    let shadowYOffset: CGFloat
    let meshGradient: TimelineView<AnimationTimelineSchedule, MeshGradient>
    @State private var logoWidth: CGFloat?
    
    public init(
        cornerRadius: CGFloat = 12,
        shadowYOffset: CGFloat = 0,
        meshGradient: TimelineView<AnimationTimelineSchedule, MeshGradient> = WXYCBackgroundMeshAnimation().meshGradient
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
        .onPreferenceChange(LogoWidthPreferenceKey.self) { width in
            logoWidth = width
        }
    }
}

#Preview {
    PlaceholderArtworkView(
        cornerRadius: 12,
        shadowYOffset: 2,
        meshGradient: WXYCBackgroundMeshAnimation().meshGradient
    )
    .background(WXYCBackground())
}
