//
//  StitchableMetalRenderer.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/20/25.
//

import MetalKit
import simd

/// MTKViewDelegate implementation for rendering stitchable shaders via Metal.
/// Eliminates CPU overhead from SwiftUI's TimelineView by rendering directly.
public final class StitchableMetalRenderer: NSObject, MTKViewDelegate {
    /// Uniforms struct matching the Metal side.
    struct Uniforms {
        var resolution: SIMD2<Float>
        var time: Float
        var displayScale: Float
    }

    private var device: MTLDevice!
    private var queue: MTLCommandQueue!
    private var pipeline: MTLRenderPipelineState!

    private var startTime = CACurrentMediaTime()
    private let wallpaper: LoadedWallpaper

    init(wallpaper: LoadedWallpaper) {
        self.wallpaper = wallpaper
        super.init()
    }

    func configure(view: MTKView) {
        guard let device = view.device else { return }
        self.device = device
        self.queue = device.makeCommandQueue()

        let renderer = wallpaper.manifest.renderer

        // Use the fragment function from manifest (required for MTKView rendering)
        guard let fragmentFn = renderer.fragmentFunction else {
            print("StitchableMetalRenderer: No fragmentFunction specified in manifest")
            return
        }

        // Vertex function is always fullscreenVertex (inlined in each shader file)
        let vertexFn = "fullscreenVertex"

        // Load from package bundle
        guard let library = try? device.makeDefaultLibrary(bundle: Bundle.module) else {
            print("StitchableMetalRenderer: Failed to load Metal library from bundle")
            return
        }

        guard let vfn = library.makeFunction(name: vertexFn) else {
            print("StitchableMetalRenderer: Vertex function '\(vertexFn)' not found")
            return
        }

        guard let ffn = library.makeFunction(name: fragmentFn) else {
            print("StitchableMetalRenderer: Fragment function '\(fragmentFn)' not found")
            return
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = view.colorPixelFormat

        do {
            self.pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            print("StitchableMetalRenderer: Failed to create pipeline: \(error)")
        }
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }

    public func draw(in view: MTKView) {
        guard
            let pipeline,
            let queue,
            let rpd = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable
        else { return }

        let now = CACurrentMediaTime()
        let timeScale = wallpaper.manifest.renderer.timeScale ?? 1.0
        let t = Float(now - startTime) * timeScale

        // Calculate display scale from drawable vs bounds
        #if os(iOS) || os(tvOS)
        let scale = Float(view.contentScaleFactor)
        #else
        let scale = Float(view.drawableSize.width / max(view.bounds.width, 1))
        #endif

        var uniforms = Uniforms(
            resolution: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
            time: t,
            displayScale: scale
        )

        guard let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: rpd)
        else { return }

        enc.setRenderPipelineState(pipeline)
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)

        // Fullscreen triangle
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }
}
