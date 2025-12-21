//
//  MultiPassMetalView.swift
//  Wallpaper
//
//  Created by Claude on 12/20/25.
//

import SwiftUI
import MetalKit

#if os(macOS)
private typealias ViewRepresentable = NSViewRepresentable
#else
private typealias ViewRepresentable = UIViewRepresentable
#endif

/// SwiftUI wrapper for multi-pass shaders rendered via MTKView.
/// Supports intermediate render targets, feedback loops, and post-processing chains.
public struct MultiPassMetalView: ViewRepresentable {
    let wallpaper: LoadedWallpaper
    var audioData: AudioData?

    public init(wallpaper: LoadedWallpaper, audioData: AudioData? = nil) {
        self.wallpaper = wallpaper
        self.audioData = audioData
    }

    public func makeCoordinator() -> MultiPassMetalRenderer {
        MultiPassMetalRenderer(wallpaper: wallpaper)
    }

#if os(macOS)
    public func makeNSView(context: Context) -> MTKView { makeView(context: context) }

    public func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.updateAudioData(audioData)
    }
#else
    public func makeUIView(context: Context) -> MTKView { makeView(context: context) }

    public func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.updateAudioData(audioData)
    }
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
        context.coordinator.updateAudioData(audioData)
        view.delegate = context.coordinator

        return view
    }
}
