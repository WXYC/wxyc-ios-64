//
//  MetalWallpaperView.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/22/25.
//

import SwiftUI
import MetalKit

#if os(macOS)
private typealias ViewRepresentable = NSViewRepresentable
#else
private typealias ViewRepresentable = UIViewRepresentable
#endif

/// Unified SwiftUI wrapper for Metal-based wallpaper rendering.
/// Supports both simple precompiled shaders and runtime-compiled shaders with directive stores.
public struct MetalWallpaperView: ViewRepresentable {
    @Environment(\.wallpaperAnimationStartTime) private var animationStartTime
    @Environment(\.wallpaperQualityProfile) private var qualityProfile

    let theme: LoadedTheme
    let directiveStore: ShaderDirectiveStore?

    public init(theme: LoadedTheme, directiveStore: ShaderDirectiveStore? = nil) {
        self.theme = theme
        self.directiveStore = directiveStore
    }

    public func makeCoordinator() -> MetalWallpaperRenderer {
        MetalWallpaperRenderer(
            theme: theme,
            directiveStore: directiveStore,
            animationStartTime: animationStartTime,
            qualityProfile: qualityProfile
        )
    }

#if os(macOS)
    public func makeNSView(context: Context) -> MTKView { makeView(context: context) }
    public func updateNSView(_ nsView: MTKView, context: Context) { }
#else
    public func makeUIView(context: Context) -> MTKView { makeView(context: context) }
    public func updateUIView(_ uiView: MTKView, context: Context) { }
#endif

    private func makeView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return MTKView()
        }

        let view = MTKView(frame: .zero, device: device)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60

        context.coordinator.configure(view: view)
        view.delegate = context.coordinator

        return view
    }
}
