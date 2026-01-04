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

    /// Intermediate texture for scaled rendering during thermal throttling.
    private var scaledRenderTarget = ScaledRenderTarget()

    /// Sampler for upscaling the intermediate texture to the drawable.
    private var upscaleSampler: MTLSamplerState?

    /// Pipeline for blitting the scaled texture to the drawable.
    private var blitPipeline: MTLRenderPipelineState?

    /// The start time in CACurrentMediaTime's time base, computed from the shared Date-based start time.
    private let startTime: CFTimeInterval
    private let theme: LoadedTheme
    private let directiveStore: ShaderDirectiveStore?
    private var runtimeCompiler: RuntimeShaderCompiler?
    private var pixelFormat: MTLPixelFormat = .bgra8Unorm
    private var directiveObservationTask: Task<Void, Never>?

    /// Reference to the adaptive thermal controller for continuous FPS/scale optimization.
    private let thermalController = AdaptiveThermalController.shared

    /// Whether this renderer uses rawMetal mode (noise texture, sampler, rawMetal uniforms).
    private var usesRawMetalMode: Bool {
        theme.manifest.renderer.type == .rawMetal
    }

    init(theme: LoadedTheme, directiveStore: ShaderDirectiveStore? = nil, animationStartTime: Date) {
        self.theme = theme
        self.directiveStore = directiveStore
        // Convert the Date-based start time to CACurrentMediaTime's time base.
        // This ensures Metal rendering is synchronized with SwiftUI's TimelineView-based renderers.
        let elapsedSinceStart = Date().timeIntervalSince(animationStartTime)
        self.startTime = CACurrentMediaTime() - elapsedSinceStart
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

        // Set active shader for thermal optimization
        Task {
            await thermalController.setActiveShader(theme.manifest.id)
        }

        let renderer = theme.manifest.renderer

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

        // Set up upscale sampler for thermal throttling
        setUpUpscaleSampler(device: device)
        setUpBlitPipeline(device: device, pixelFormat: view.colorPixelFormat)
    }

    private func setUpUpscaleSampler(device: MTLDevice) {
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        upscaleSampler = device.makeSamplerState(descriptor: descriptor)
    }

    private func setUpBlitPipeline(device: MTLDevice, pixelFormat: MTLPixelFormat) {
        guard let library = try? device.makeDefaultLibrary(bundle: Bundle.module) else { return }
        guard let vfn = library.makeFunction(name: "fullscreenVertex") else { return }
        guard let ffn = library.makeFunction(name: "blitFragment") else { return }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = pixelFormat

        blitPipeline = try? device.makeRenderPipelineState(descriptor: desc)
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
        buildRuntimePipeline(renderer: theme.manifest.renderer, pixelFormat: pixelFormat)
    }

    // MARK: - MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }

    public func draw(in view: MTKView) {
        guard
            let pipeline,
            let queue,
            let drawable = view.currentDrawable
        else { return }

        // Get current thermal optimization values
        let resolutionScale = thermalController.currentScale
        let targetFPS = Int(thermalController.currentFPS)

        // Update FPS if changed
        if view.preferredFramesPerSecond != targetFPS {
            view.preferredFramesPerSecond = targetFPS
        }

        let now = CACurrentMediaTime()
        let timeScale = theme.manifest.renderer.timeScale ?? 1.0
        let t = Float(now - startTime) * timeScale

        // Update scaled render target
        _ = scaledRenderTarget.update(
            device: device,
            viewSize: view.drawableSize,
            scale: resolutionScale,
            pixelFormat: pixelFormat
        )

        guard let cmd = queue.makeCommandBuffer() else { return }

        if resolutionScale < 1.0, let scaledTexture = scaledRenderTarget.renderTexture {
            // Render to scaled texture, then upscale to drawable
            renderToScaledTexture(cmd: cmd, texture: scaledTexture, time: t)
            blitToDrawable(cmd: cmd, texture: scaledTexture, drawable: drawable, view: view)
        } else {
            // Render directly to drawable
            guard let rpd = view.currentRenderPassDescriptor else { return }
            renderDirectly(cmd: cmd, descriptor: rpd, drawableSize: view.drawableSize, time: t, view: view)
        }

        cmd.present(drawable)
        cmd.commit()
    }

    private func renderToScaledTexture(cmd: MTLCommandBuffer, texture: MTLTexture, time: Float) {
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = texture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }

        enc.setRenderPipelineState(pipeline)

        let scaledSize = scaledRenderTarget.scaledSize

        if usesRawMetalMode {
            var uniforms = RawMetalUniforms(
                resolution: SIMD2(Float(scaledSize.width), Float(scaledSize.height)),
                time: time
            )
            enc.setFragmentBytes(&uniforms, length: MemoryLayout<RawMetalUniforms>.stride, index: 0)
            enc.setFragmentTexture(noiseTex, index: 0)
            enc.setFragmentSamplerState(sampler, index: 0)

            // Pass custom parameters in buffer index 1 (up to 8 floats)
            let parameterStore = theme.parameterStore
            let params = theme.manifest.parameters
            if !params.isEmpty {
                var paramValues: [Float] = []
                for param in params.prefix(8) {
                    paramValues.append(parameterStore.floatValue(for: param.id))
                }
                while paramValues.count < 8 {
                    paramValues.append(0)
                }
                paramValues.withUnsafeBytes { ptr in
                    enc.setFragmentBytes(ptr.baseAddress!, length: 8 * MemoryLayout<Float>.stride, index: 1)
                }
            }
        } else {
            var uniforms = StitchableUniforms(
                resolution: SIMD2(Float(scaledSize.width), Float(scaledSize.height)),
                time: time,
                displayScale: 1.0
            )
            enc.setFragmentBytes(&uniforms, length: MemoryLayout<StitchableUniforms>.stride, index: 0)
        }

        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    private func blitToDrawable(cmd: MTLCommandBuffer, texture: MTLTexture, drawable: CAMetalDrawable, view: MTKView) {
        guard let blitPipeline, let upscaleSampler else { return }

        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = drawable.texture
        rpd.colorAttachments[0].loadAction = .dontCare
        rpd.colorAttachments[0].storeAction = .store

        guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }

        enc.setRenderPipelineState(blitPipeline)
        enc.setFragmentTexture(texture, index: 0)
        enc.setFragmentSamplerState(upscaleSampler, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    private func renderDirectly(cmd: MTLCommandBuffer, descriptor: MTLRenderPassDescriptor, drawableSize: CGSize, time: Float, view: MTKView) {
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        enc.setRenderPipelineState(pipeline)

        if usesRawMetalMode {
            var uniforms = RawMetalUniforms(
                resolution: SIMD2(Float(drawableSize.width), Float(drawableSize.height)),
                time: time
            )
            enc.setFragmentBytes(&uniforms, length: MemoryLayout<RawMetalUniforms>.stride, index: 0)
            enc.setFragmentTexture(noiseTex, index: 0)
            enc.setFragmentSamplerState(sampler, index: 0)

            let parameterStore = theme.parameterStore
            let params = theme.manifest.parameters
            if !params.isEmpty {
                var paramValues: [Float] = []
                for param in params.prefix(8) {
                    paramValues.append(parameterStore.floatValue(for: param.id))
                }
                while paramValues.count < 8 {
                    paramValues.append(0)
                }
                paramValues.withUnsafeBytes { ptr in
                    enc.setFragmentBytes(ptr.baseAddress!, length: 8 * MemoryLayout<Float>.stride, index: 1)
                }
            }
        } else {
            #if os(iOS) || os(tvOS)
            let displayScale = Float(view.contentScaleFactor)
            #else
            let displayScale = Float(drawableSize.width / max(view.bounds.width, 1))
            #endif

            var uniforms = StitchableUniforms(
                resolution: SIMD2(Float(drawableSize.width), Float(drawableSize.height)),
                time: time,
                displayScale: displayScale
            )
            enc.setFragmentBytes(&uniforms, length: MemoryLayout<StitchableUniforms>.stride, index: 0)
        }

        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
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
