//
//  PerspexWebLatticeView.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/19/25.
//

import SwiftUI
import MetalKit
import simd

public final class PerspexWebLatticeWallpaper: Wallpaper {
    public let displayName = "Lattice"
    
    public init() {}
    
    public func makeView() -> PerspexWebLatticeView {
        PerspexWebLatticeView()
    }
    
    public func makeDebugControls() -> EmptyView? {
        nil
    }
    
    public func reset() {}
}

#if os(macOS)
typealias ViewRepresentable = NSViewRepresentable
#else
typealias ViewRepresentable = UIViewRepresentable
#endif

public struct PerspexWebLatticeView: ViewRepresentable {
    public func makeCoordinator() -> Renderer { Renderer() }
    
#if os(macOS)
    public func makeNSView(context: Context) -> MTKView { makeView(context: context) }
    public func updateNSView(_ nsView: MTKView, context: Context) { }
#else
    public func makeUIView(context: Context) -> MTKView { makeView(context: context) }
    public func updateUIView(_ uiView: MTKView, context: Context) { }
#endif
    
    private func makeView(context: Context) -> MTKView {
        let view = makeCommonMTKView()
        context.coordinator.configure(view: view)
        view.delegate = context.coordinator
        return view
    }
}

fileprivate func makeCommonMTKView() -> MTKView {
    guard let device = MTLCreateSystemDefaultDevice() else {
        return MTKView()
    }
    
    let view = MTKView(frame: .zero, device: device)
    view.colorPixelFormat = .bgra8Unorm
    view.framebufferOnly = false
    view.isPaused = false
    view.enableSetNeedsDisplay = false
    view.preferredFramesPerSecond = 60
    return view
}

// MARK: - Renderer
public final class Renderer: NSObject, MTKViewDelegate {
    struct Uniforms {
        var resolution: SIMD2<Float>
        var time: Float
        var pad: Float = 0
    }
    
    private var device: MTLDevice!
    private var queue: MTLCommandQueue!
    private var pipeline: MTLRenderPipelineState!
    private var sampler: MTLSamplerState!
    private var noiseTex: MTLTexture!
    
    private var startTime = CACurrentMediaTime()
    
    func configure(view: MTKView) {
        guard let device = view.device else { return }
        self.device = device
        self.queue = device.makeCommandQueue()
        
        // Pipeline
        let library = device.makeDefaultLibrary()
        let vfn = library?.makeFunction(name: "vertexMain")
        let ffn = library?.makeFunction(name: "fragmentMain")
        
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        
        self.pipeline = try? device.makeRenderPipelineState(descriptor: desc)
        
        // Sampler: repeat + linear
        let sDesc = MTLSamplerDescriptor()
        sDesc.minFilter = .linear
        sDesc.magFilter = .linear
        sDesc.sAddressMode = .repeat
        sDesc.tAddressMode = .repeat
        self.sampler = device.makeSamplerState(descriptor: sDesc)
        
        // iChannel0 stand-in: procedurally generated noise texture
        self.noiseTex = makeNoiseTexture(device: device, size: 256)
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
        let t = Float(now - startTime)
        
        var uniforms = Uniforms(
            resolution: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
            time: t
        )
        
        guard let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: rpd)
        else { return }
        
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        enc.setFragmentTexture(noiseTex, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)
        
        // Fullscreen triangle
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }
    
    private func makeNoiseTexture(device: MTLDevice, size: Int) -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: size,
            height: size,
            mipmapped: false
        )
        desc.usage = [.shaderRead]
        
        let tex = device.makeTexture(descriptor: desc)!
        
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let v = UInt8.random(in: 0...255)
            bytes[i + 0] = v
            bytes[i + 1] = v
            bytes[i + 2] = v
            bytes[i + 3] = 255
        }
        
        bytes.withUnsafeBytes { ptr in
            tex.replace(
                region: MTLRegionMake2D(0, 0, size, size),
                mipmapLevel: 0,
                withBytes: ptr.baseAddress!,
                bytesPerRow: size * 4
            )
        }
        
        return tex
    }
}

