//
//  RawMetalWallpaperView.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/19/25.
//

import SwiftUI
import MetalKit
import simd

#if os(macOS)
private typealias ViewRepresentable = NSViewRepresentable
#else
private typealias ViewRepresentable = UIViewRepresentable
#endif

/// Generic view for wallpapers that use raw Metal rendering with vertex/fragment shaders.
public struct RawMetalWallpaperView: ViewRepresentable {
    let wallpaper: LoadedWallpaper
    let directiveStore: ShaderDirectiveStore?

    public init(wallpaper: LoadedWallpaper, directiveStore: ShaderDirectiveStore? = nil) {
        self.wallpaper = wallpaper
        self.directiveStore = directiveStore
    }

    public func makeCoordinator() -> RawMetalRenderer {
        RawMetalRenderer(wallpaper: wallpaper, directiveStore: directiveStore)
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

// MARK: - Renderer

public final class RawMetalRenderer: NSObject, MTKViewDelegate {
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
    private let wallpaper: LoadedWallpaper
    private let directiveStore: ShaderDirectiveStore?
    private var runtimeCompiler: RuntimeShaderCompiler?
    private var pixelFormat: MTLPixelFormat = .bgra8Unorm

    init(wallpaper: LoadedWallpaper, directiveStore: ShaderDirectiveStore? = nil) {
        self.wallpaper = wallpaper
        self.directiveStore = directiveStore
        super.init()
    }

    func configure(view: MTKView) {
        guard let device = view.device else { return }
        self.device = device
        self.queue = device.makeCommandQueue()
        self.pixelFormat = view.colorPixelFormat

        let renderer = wallpaper.manifest.renderer

        // Check if we should use runtime compilation (shader source available)
        if let shaderFile = renderer.shaderFile,
           let shaderURL = Bundle.module.url(forResource: shaderFile.replacingOccurrences(of: ".metal", with: ""), withExtension: "metal"),
           let shaderSource = try? String(contentsOf: shaderURL, encoding: .utf8) {
            // Use runtime compilation
            setUpRuntimeCompilation(device: device, shaderSource: shaderSource, renderer: renderer, pixelFormat: view.colorPixelFormat)
        } else {
            // Use precompiled library
            setUpPrecompiledPipeline(device: device, renderer: renderer, pixelFormat: view.colorPixelFormat)
        }

        // Sampler: repeat + linear
        let sDesc = MTLSamplerDescriptor()
        sDesc.minFilter = .linear
        sDesc.magFilter = .linear
        sDesc.sAddressMode = .repeat
        sDesc.tAddressMode = .repeat
        self.sampler = device.makeSamplerState(descriptor: sDesc)

        // Noise texture for shaders that need it
        self.noiseTex = makeNoiseTexture(device: device, size: 256)
    }

    private func setUpRuntimeCompilation(device: MTLDevice, shaderSource: String, renderer: RendererConfiguration, pixelFormat: MTLPixelFormat) {
        runtimeCompiler = RuntimeShaderCompiler(device: device, shaderSource: shaderSource)

        // Configure directive store with available directives
        if let store = directiveStore, let compiler = runtimeCompiler {
            store.configure(with: compiler.availableDirectives)

            // Apply saved states to compiler
            for directive in compiler.availableDirectives {
                compiler.setDirective(directive, enabled: store.isEnabled(directive))
            }

            // Set up callback for recompilation
            store.onDirectivesChanged = { [weak self] in
                self?.recompileShader()
            }
        }

        // Build initial pipeline
        buildRuntimePipeline(renderer: renderer, pixelFormat: pixelFormat)
    }

    private func setUpPrecompiledPipeline(device: MTLDevice, renderer: RendererConfiguration, pixelFormat: MTLPixelFormat) {
        let vertexFn = renderer.vertexFunction ?? "vertexMain"
        let fragmentFn = renderer.fragmentFunction ?? "fragmentMain"

        let library = try? device.makeDefaultLibrary(bundle: Bundle.module)
        let vfn = library?.makeFunction(name: vertexFn)
        let ffn = library?.makeFunction(name: fragmentFn)

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = pixelFormat

        self.pipeline = try? device.makeRenderPipelineState(descriptor: desc)
    }

    private func buildRuntimePipeline(renderer: RendererConfiguration, pixelFormat: MTLPixelFormat) {
        guard let compiler = runtimeCompiler else { return }

        let vertexFn = renderer.vertexFunction ?? "fullscreenVertex"
        let fragmentFn = renderer.fragmentFunction ?? "fragmentMain"

        do {
            // Load vertex function from precompiled library (shared vertex shader)
            let precompiledLib = try? device.makeDefaultLibrary(bundle: Bundle.module)
            let vfn = precompiledLib?.makeFunction(name: vertexFn)

            // Load fragment function from runtime-compiled library
            let ffn = try compiler.makeFunction(name: fragmentFn)

            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vfn
            desc.fragmentFunction = ffn
            desc.colorAttachments[0].pixelFormat = pixelFormat

            self.pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            print("RuntimeShaderCompiler: Failed to build pipeline: \(error)")
        }
    }

    private func recompileShader() {
        guard let compiler = runtimeCompiler, let store = directiveStore else { return }

        // Apply current directive states to compiler
        for directive in compiler.availableDirectives {
            compiler.setDirective(directive, enabled: store.isEnabled(directive))
        }

        // Rebuild pipeline
        buildRuntimePipeline(renderer: wallpaper.manifest.renderer, pixelFormat: pixelFormat)
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
            // Independent random values per channel (needed for shaders like LavaLite)
            bytes[i + 0] = UInt8.random(in: 0...255)  // R
            bytes[i + 1] = UInt8.random(in: 0...255)  // G
            bytes[i + 2] = UInt8.random(in: 0...255)  // B
            bytes[i + 3] = UInt8.random(in: 0...255)  // A
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
