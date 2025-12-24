//
//  MetalWallpaperRenderer.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/22/25.
//

import Core
import MetalKit
import simd

@MainActor
public final class MetalWallpaperRenderer: NSObject, MTKViewDelegate {
    /// Uniforms for stitchable shaders (resolution, time, displayScale).
    struct StitchableUniforms {
        var resolution: SIMD2<Float>
        var time: Float
        var displayScale: Float
    }

    /// Uniforms for rawMetal shaders (resolution, time, pad).
    struct RawMetalUniforms {
        var resolution: SIMD2<Float>
        var time: Float
        var pad: Float = 0
    }

    private var device: MTLDevice!
    private var queue: MTLCommandQueue!
    private var pipeline: MTLRenderPipelineState!
    private var sampler: MTLSamplerState?
    private var noiseTex: MTLTexture?

    private var startTime: CFTimeInterval = CACurrentMediaTime()
    private let startTimeOffset = CFTimeInterval.random(in: 0.0...10.0)
    private let wallpaper: LoadedWallpaper
    private let directiveStore: ShaderDirectiveStore?
    private var runtimeCompiler: RuntimeShaderCompiler?
    private var pixelFormat: MTLPixelFormat = .bgra8Unorm
    private var directiveObservationTask: Task<Void, Never>?

    /// Whether this renderer uses rawMetal mode (noise texture, sampler, rawMetal uniforms).
    private var usesRawMetalMode: Bool {
        wallpaper.manifest.renderer.type == .rawMetal
    }

    init(wallpaper: LoadedWallpaper, directiveStore: ShaderDirectiveStore? = nil) {
        self.wallpaper = wallpaper
        self.directiveStore = directiveStore
        super.init()
    }

    deinit {
        directiveObservationTask?.cancel()
    }

    func configure(view: MTKView) {
        guard let device = view.device else { return }
        self.device = device
        self.queue = device.makeCommandQueue()
        self.pixelFormat = view.colorPixelFormat

        let renderer = wallpaper.manifest.renderer

        if usesRawMetalMode {
            // RawMetal mode: check for runtime compilation, set up noise texture and sampler
            if let shaderFile = renderer.shaderFile,
               let shaderURL = Bundle.module.url(forResource: shaderFile.replacing(".metal", with: ""), withExtension: "metal"),
               let shaderSource = try? String(contentsOf: shaderURL, encoding: .utf8) {
                setUpRuntimeCompilation(device: device, shaderSource: shaderSource, renderer: renderer, pixelFormat: view.colorPixelFormat)
            } else {
                setUpPrecompiledPipeline(device: device, renderer: renderer, pixelFormat: view.colorPixelFormat)
            }

            // Sampler: repeat + linear (for noise texture sampling)
            let sDesc = MTLSamplerDescriptor()
            sDesc.minFilter = .linear
            sDesc.magFilter = .linear
            sDesc.sAddressMode = .repeat
            sDesc.tAddressMode = .repeat
            self.sampler = device.makeSamplerState(descriptor: sDesc)

            // Noise texture for shaders that need it
            self.noiseTex = makeNoiseTexture(device: device, size: 256)
        } else {
            // Stitchable mode: simple precompiled pipeline, no textures
            setUpStitchablePipeline(device: device, renderer: renderer, pixelFormat: view.colorPixelFormat)
        }
    }

    // MARK: - Pipeline Setup

    private func setUpStitchablePipeline(device: MTLDevice, renderer: RendererConfiguration, pixelFormat: MTLPixelFormat) {
        guard let fragmentFn = renderer.fragmentFunction else {
            print("MetalWallpaperRenderer: No fragmentFunction specified in manifest")
            return
        }

        let vertexFn = "fullscreenVertex"

        guard let library = try? device.makeDefaultLibrary(bundle: Bundle.module) else {
            print("MetalWallpaperRenderer: Failed to load Metal library from bundle")
            return
        }

        guard let vfn = library.makeFunction(name: vertexFn) else {
            print("MetalWallpaperRenderer: Vertex function '\(vertexFn)' not found")
            return
        }

        guard let ffn = library.makeFunction(name: fragmentFn) else {
            print("MetalWallpaperRenderer: Fragment function '\(fragmentFn)' not found")
            return
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = pixelFormat

        do {
            self.pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            print("MetalWallpaperRenderer: Failed to create pipeline: \(error)")
        }
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

            // Observe directive changes for recompilation
            directiveObservationTask = Task { @MainActor [weak self] in
                for await _ in Observations({ store.availableDirectives }) {
                    self?.recompileShader()
                }
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
            print("MetalWallpaperRenderer: Failed to build runtime pipeline: \(error)")
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

    // MARK: - MTKViewDelegate

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
        let t = Float(now - startTime + startTimeOffset) * timeScale

        guard let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: rpd)
        else { return }

        enc.setRenderPipelineState(pipeline)

        if usesRawMetalMode {
            // RawMetal uniforms and textures
            var uniforms = RawMetalUniforms(
                resolution: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
                time: t
            )
            enc.setFragmentBytes(&uniforms, length: MemoryLayout<RawMetalUniforms>.stride, index: 0)
            enc.setFragmentTexture(noiseTex, index: 0)
            enc.setFragmentSamplerState(sampler, index: 0)
        } else {
            // Stitchable uniforms (no textures)
            #if os(iOS) || os(tvOS)
            let scale = Float(view.contentScaleFactor)
            #else
            let scale = Float(view.drawableSize.width / max(view.bounds.width, 1))
            #endif

            var uniforms = StitchableUniforms(
                resolution: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
                time: t,
                displayScale: scale
            )
            enc.setFragmentBytes(&uniforms, length: MemoryLayout<StitchableUniforms>.stride, index: 0)
        }

        // Fullscreen triangle
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }

    // MARK: - Noise Texture

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
