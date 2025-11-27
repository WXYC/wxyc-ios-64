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
                    .glassEffect(
                        .clear
                            .tint(
                                Color(
                                    hue: 248 / 360,
                                    saturation: 100 / 100,
                                    brightness: 100 / 100,
                                    opacity: 0.25
                                )
                            )
                            .interactive(),
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
                    .glassEffect(.clear, in: WXYCLogoShape())
                    .preferredColorScheme(.light)
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

struct MeshGradientAnimation {
    public let shadowOffsetAtTop: CGFloat = -3
    public let shadowOffsetAtBottom: CGFloat = 3
    
    @State private var colors = Self.randomColors()
    @State private var timeOffset: Int = (-10..<10).randomElement()!
    
    private static func randomColors() -> [Color] {
        (0..<16).map { _ in palette.randomElement()! }
    }
    
    private static let palette: [Color] = [
        .indigo,
        .orange,
        .pink,
        .purple,
        .yellow,
        .blue,
        .green,
    ]

    var meshGradientAnimation: TimelineView<AnimationTimelineSchedule, MeshGradient> {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSince1970 + TimeInterval(timeOffset)
            let offsetX = Float(sin(time)) * 0.25
            let offsetY = Float(cos(time)) * 0.25
            
            MeshGradient(
                width: 4,
                height: 4,
                points: [
                    [0.0, 0.0],
                    [0.3, 0.0],
                    [0.7, 0.0],
                    [1.0, 0.0],
                    [0.0, 0.3],
                    [0.2 + offsetX, 0.4 + offsetY],
                    [0.7 + offsetX, 0.2 + offsetY],
                    [1.0, 0.3],
                    [0.0, 0.7],
                    [0.3 + offsetX, 0.8],
                    [0.7 + offsetX, 0.6],
                    [1.0, 0.7],
                    [0.0, 1.0],
                    [0.3, 1.0],
                    [0.7, 1.0],
                    [1.0, 1.0]
                ],
                colors: colors
            )
        }
    }
}

#Preview {
    PlaceholderArtworkView(
        cornerRadius: 12,
        shadowYOffset: 2,
        meshGradient: MeshGradientAnimation().meshGradientAnimation
    )
    .background(WXYCBackground())
}
