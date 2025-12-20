//
//  SpiralView.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/18/25.
//

import SwiftUI
import Observation
import WallpaperMacros

@Wallpaper
@Observable
public final class SpiralWallpaper: WallpaperProtocol {
    public let displayName = "Spiral"

    public func configure() {}

    public func makeView() -> SpiralView {
        SpiralView()
    }

    public func makeDebugControls() -> EmptyView? {
        nil
    }

    public func reset() {}
}

/// Animated spiral shader effect
public struct SpiralView: View {
    private let shaderFunction = ShaderFunction(
        library: ShaderLibrary.bundle(.module),
        name: "spiral"
    )

    public var body: some View {
        TimelineView(.animation) { timeline in
            GeometryReader { geo in
                let t = Float(timeline.date.timeIntervalSinceReferenceDate)
                let w = Float(geo.size.width)
                let h = Float(geo.size.height)

                let shader = Shader(function: shaderFunction, arguments: [
                    .float(w),
                    .float(h),
                    .float(t)
                ])

                Rectangle()
                    .colorEffect(shader)
                    .ignoresSafeArea()
            }
        }
    }
}
