//
//  MetalWallpaperRenderer.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/19/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Core
import MetalKit
import simd

#if os(iOS) || os(tvOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
public final class MetalWallpaperRenderer: NSObject, MTKViewDelegate {
    /// Uniforms for stitchable shaders (resolution, time, displayScale).
    struct StitchableUniforms {
        var resolution: SIMD2<Float>
        var time: Float
        var displayScale: Float
    }

    /// Uniforms for rawMetal shaders (resolution, time, lod).
    struct RawMetalUniforms {
        var resolution: SIMD2<Float>
        var time: Float
        var lod: Float = 1.0
    }

    /// Uniforms for frame interpolation blending.
    struct InterpolationUniforms {
        var blendFactor: Float
    }

    // MARK: - Ring Buffer Constants

    /// Number of uniform buffers in the ring (triple buffering).
    private static let uniformBufferCount = 3

    /// Size of the uniform buffer (holds uniforms at offset 0, parameters at offset 256).
    /// Metal requires constant buffer offsets to be 256-byte aligned.
    private static let uniformBufferSize = 512

    /// Offset for custom shader parameters (must be 256-byte aligned for Metal).
    private static let parameterBufferOffset = 256

    // MARK: - Core Metal Objects

    private var device: MTLDevice!
    private var queue: MTLCommandQueue!
    private var pipeline: MTLRenderPipelineState!
    private var sampler: MTLSamplerState?
    private var noiseTex: MTLTexture?

    /// Compute pipeline manager for compute-based wallpapers (physarum, etc.)
    private var computeManager: ComputePipelineManager?

    // MARK: - Pre-allocated Uniform Buffers (Ring Buffer)

    /// Ring buffer of pre-allocated uniform buffers to avoid per-frame allocation.
    private var uniformBuffers: [MTLBuffer] = []

    /// Current index in the uniform buffer ring.
    private var uniformBufferIndex = 0

    /// Intermediate texture for scaled rendering during thermal throttling.
    private var scaledRenderTarget = ScaledRenderTarget()

    /// Sampler for upscaling the intermediate texture to the drawable.
    private var upscaleSampler: MTLSamplerState?

    /// Pipeline for blitting the scaled texture to the drawable.
    private var blitPipeline: MTLRenderPipelineState?

    /// Pipeline for frame interpolation blending.
    private var interpolationPipeline: MTLRenderPipelineState?

    /// Frame interpolator for caching and blending frames.
    private var frameInterpolator = FrameInterpolator()

    /// The start time in CACurrentMediaTime's time base, computed from the shared Date-based start time.
    private let startTime: CFTimeInterval
    private let theme: LoadedTheme
    private let directiveStore: ShaderDirectiveStore?
    private var runtimeCompiler: RuntimeShaderCompiler?
    private var pixelFormat: MTLPixelFormat = .bgra8Unorm
    private var directiveObservationTask: Task<Void, Never>?

    /// Optional fixed quality profile that overrides adaptive thermal optimization.
    private let qualityProfile: QualityProfile?

    /// Reference to the adaptive thermal controller for continuous FPS/scale optimization.
    /// Only used when `qualityProfile` is nil.
    private let qualityController = AdaptiveQualityController.shared

    /// Frame rate monitor for early performance detection.
    private var frameRateMonitor = FrameRateMonitor()

    /// Timestamp of last frame start for duration measurement.
    private var lastFrameStart: CFTimeInterval = 0

    // MARK: - Cached Thermal Values

    /// Cached resolution scale from thermal controller (updated periodically).
    private var cachedResolutionScale: Float = 1.0

    /// Cached target FPS from thermal controller (updated periodically).
    private var cachedTargetFPS: Int = 60

    /// Cached LOD from thermal controller (updated periodically).
    private var cachedLOD: Float = 1.0

    /// Cached interpolation enabled state from thermal controller (updated periodically).
    private var cachedInterpolationEnabled: Bool = false

    /// Cached shader FPS from thermal controller (updated periodically).
    private var cachedShaderFPS: Float = 60.0

    /// Last seen profile reset count from thermal controller.
    /// Used to detect when to reset the frame rate monitor.
    private var lastSeenProfileResetCount: Int = 0

    // MARK: - Idle FPS Reduction

    /// Whether we're currently in theme picker mode.
    public var isInPickerMode: Bool = false {
        didSet {
            // Track the main (non-picker) renderer for snapshot capture
            if !isInPickerMode {
                Self.activeMainRenderer = self
            } else if Self.activeMainRenderer === self {
                Self.activeMainRenderer = nil
            }
        }
    }

    // MARK: - Active Renderer Tracking

    /// Weak reference to the main (non-picker) renderer for snapshot capture.
    private static weak var activeMainRenderer: MetalWallpaperRenderer?

    /// Captures a snapshot from the currently active main renderer.
    /// - Returns: A Core.Image snapshot (UIImage/NSImage), or nil if no main renderer is active.
    public static func captureMainSnapshot() -> Core.Image? {
        activeMainRenderer?.captureSnapshot()
    }

    /// FPS to use when in idle/picker mode.
    private static let idleFPS: Int = 30

    /// Whether this renderer uses rawMetal mode (noise texture, sampler, rawMetal uniforms).
    private var usesRawMetalMode: Bool {
        theme.manifest.renderer.type == .rawMetal
    }

    /// Whether this renderer uses compute shaders (particle simulations, etc.)
    private var usesComputeMode: Bool {
        theme.manifest.renderer.type == .compute
    }

    init(
        theme: LoadedTheme,
        directiveStore: ShaderDirectiveStore? = nil,
        animationStartTime: Date,
        qualityProfile: QualityProfile? = nil
    ) {
        self.theme = theme
        self.directiveStore = directiveStore
        self.qualityProfile = qualityProfile
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

        // Pre-allocate uniform buffers (ring buffer)
        setUpUniformBuffers(device: device)

        // Set up thermal optimization only when no fixed quality profile is set
        if let profile = qualityProfile {
            // Use fixed quality profile settings
            view.preferredFramesPerSecond = Int(profile.wallpaperFPS)
        } else {
            // Set active shader for adaptive thermal optimization
            Task {
                await qualityController.setActiveShader(theme.manifest.id)
            }
        }

        let renderer = theme.manifest.renderer

        if usesComputeMode {
            // Compute mode: particle simulations, physarum, etc.
            setUpComputePipeline(device: device, renderer: renderer, pixelFormat: view.colorPixelFormat)

            // Set up sampler for trail map rendering
            let sDesc = MTLSamplerDescriptor()
            sDesc.minFilter = .linear
            sDesc.magFilter = .linear
            sDesc.sAddressMode = .clampToEdge
            sDesc.tAddressMode = .clampToEdge
            self.sampler = device.makeSamplerState(descriptor: sDesc)
        } else if usesRawMetalMode {
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
        setUpInterpolationPipeline(device: device, pixelFormat: view.colorPixelFormat)

        // Register as the main renderer if not in picker mode (no quality profile override)
        if qualityProfile == nil {
            Self.activeMainRenderer = self
        }
    }

    /// Pre-allocates uniform buffers to avoid per-frame allocation overhead.
    private func setUpUniformBuffers(device: MTLDevice) {
        uniformBuffers = (0..<Self.uniformBufferCount).compactMap { _ in
            device.makeBuffer(length: Self.uniformBufferSize, options: .storageModeShared)
        }
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

    private func setUpInterpolationPipeline(device: MTLDevice, pixelFormat: MTLPixelFormat) {
        guard let library = try? device.makeDefaultLibrary(bundle: Bundle.module) else { return }
        guard let vfn = library.makeFunction(name: "fullscreenVertex") else { return }
        guard let ffn = library.makeFunction(name: "interpolateFragment") else { return }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = pixelFormat

        interpolationPipeline = try? device.makeRenderPipelineState(descriptor: desc)
    }

    // MARK: - Pipeline Setup

    private func setUpComputePipeline(device: MTLDevice, renderer: RendererConfiguration, pixelFormat: MTLPixelFormat) {
        guard let computeConfig = renderer.compute else {
            print("MetalWallpaperRenderer: Compute configuration missing for compute renderer type")
            return
        }

        guard let library = try? device.makeDefaultLibrary(bundle: Bundle.module) else {
            print("MetalWallpaperRenderer: Failed to load Metal library from bundle")
            return
        }

        // Create compute pipeline manager
        let manager = ComputePipelineManager(device: device)

        do {
            try manager.setUp(config: computeConfig, library: library, pixelFormat: pixelFormat)
            self.computeManager = manager
        } catch {
            print("MetalWallpaperRenderer: Failed to set up compute pipeline: \(error)")
        }
    }

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
        let vertexFn = renderer.vertexFunction ?? "fullscreenVertex"
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
        // Compute mode uses computeManager instead of pipeline
        let hasValidPipeline = pipeline != nil || (usesComputeMode && computeManager?.isReady == true)

        guard
            hasValidPipeline,
            let queue,
            let drawable = view.currentDrawable,
            !uniformBuffers.isEmpty
        else { return }

        // Get quality values from fixed profile or thermal controller
        let resolutionScale: Float
        let targetFPS: Int
        let lod: Float
        let interpolationEnabled: Bool
        let shaderFPS: Float

        if let profile = qualityProfile {
            // Use fixed quality profile
            resolutionScale = profile.scale
            targetFPS = Int(profile.wallpaperFPS)
            lod = profile.lod
            interpolationEnabled = profile.interpolationEnabled
            shaderFPS = profile.shaderFPS
        } else {
            // Check if profile was reset - if so, reset frame rate monitor to avoid stale samples
            let currentResetCount = qualityController.profileResetCount
            if currentResetCount != lastSeenProfileResetCount {
                lastSeenProfileResetCount = currentResetCount
                frameRateMonitor.reset()
                lastFrameStart = 0
                // Immediately update cached values to reflect new profile settings
                cachedResolutionScale = qualityController.effectiveScale
                cachedTargetFPS = Int(qualityController.effectiveWallpaperFPS)
                cachedLOD = qualityController.effectiveLOD
                cachedInterpolationEnabled = qualityController.effectiveInterpolationEnabled
                cachedShaderFPS = qualityController.effectiveShaderFPS
            }

            // Measure frame duration for periodic thermal value updates
            let frameStart = CACurrentMediaTime()
            if lastFrameStart > 0 {
                let frameDuration = frameStart - lastFrameStart
                // Update cached thermal values periodically (every ~1 second)
                if let measuredFPS = frameRateMonitor.recordFrame(duration: frameDuration) {
                    // Report measured FPS to trigger reactive throttling when GPU struggles
                    qualityController.reportMeasuredFPS(measuredFPS)
                    cachedResolutionScale = qualityController.effectiveScale
                    cachedTargetFPS = Int(qualityController.effectiveWallpaperFPS)
                    cachedLOD = qualityController.effectiveLOD
                    cachedInterpolationEnabled = qualityController.effectiveInterpolationEnabled
                    cachedShaderFPS = qualityController.effectiveShaderFPS
                }
            }
            lastFrameStart = frameStart

            // Use cached thermal values (updated every ~1 second)
            resolutionScale = cachedResolutionScale
            lod = cachedLOD

            // Apply idle FPS reduction when in picker mode
            if isInPickerMode {
                targetFPS = Self.idleFPS
                interpolationEnabled = false
                shaderFPS = Float(Self.idleFPS)
            } else {
                targetFPS = cachedTargetFPS
                interpolationEnabled = cachedInterpolationEnabled
                shaderFPS = cachedShaderFPS
            }

            // Update FPS if changed
            if view.preferredFramesPerSecond != targetFPS {
                view.preferredFramesPerSecond = targetFPS
            }
        }

        let now = CACurrentMediaTime()
        let timeScale = theme.manifest.renderer.timeScale ?? 1.0
        let t = Float(now - startTime) * timeScale

        // Cap resolution scale by theme's maxScale (for expensive shaders)
        let cappedScale = min(resolutionScale, theme.manifest.renderer.effectiveMaxScale)

        // Update scaled render target
        _ = scaledRenderTarget.update(
            device: device,
            viewSize: view.drawableSize,
            scale: cappedScale,
            pixelFormat: pixelFormat
        )

        // Get next buffer from ring
        let uniformBuffer = uniformBuffers[uniformBufferIndex]
        uniformBufferIndex = (uniformBufferIndex + 1) % uniformBuffers.count

        guard let cmd = queue.makeCommandBuffer() else { return }

        // Compute mode: execute compute passes and render
        if usesComputeMode, let manager = computeManager {
            // Set up persistent textures if size changed
            manager.setUpPersistentTextures(
                configs: theme.manifest.renderer.compute?.persistentTextures,
                size: view.drawableSize
            )

            // Populate uniforms for compute shaders
            let bufferPtr = uniformBuffer.contents()
            var uniforms = RawMetalUniforms(
                resolution: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
                time: t,
                lod: lod
            )
            memcpy(bufferPtr, &uniforms, MemoryLayout<RawMetalUniforms>.stride)

            // Execute compute passes
            manager.executeComputePasses(
                commandBuffer: cmd,
                uniforms: uniformBuffer,
                size: view.drawableSize
            )

            // Render to screen
            guard let rpd = view.currentRenderPassDescriptor else { return }
            manager.render(
                commandBuffer: cmd,
                renderPassDescriptor: rpd,
                uniforms: uniformBuffer,
                sampler: sampler
            )

            cmd.present(drawable)
            cmd.commit()
            return
        }

        if interpolationEnabled {
            // Frame interpolation mode: render shader at reduced rate, blend frames
            drawWithInterpolation(
                cmd: cmd,
                drawable: drawable,
                view: view,
                time: t,
                displayTime: now,
                shaderFPS: shaderFPS,
                resolutionScale: resolutionScale,
                lod: lod,
                uniformBuffer: uniformBuffer
            )
        } else if resolutionScale < 1.0, let scaledTexture = scaledRenderTarget.renderTexture {
            // Render to scaled texture, then upscale to drawable
            renderToScaledTexture(cmd: cmd, texture: scaledTexture, time: t, lod: lod, uniformBuffer: uniformBuffer)
            blitToDrawable(cmd: cmd, texture: scaledTexture, drawable: drawable, view: view)
        } else {
            // Render directly to drawable
            guard let rpd = view.currentRenderPassDescriptor else { return }
            renderDirectly(cmd: cmd, descriptor: rpd, drawableSize: view.drawableSize, time: t, lod: lod, view: view, uniformBuffer: uniformBuffer)
        }

        cmd.present(drawable)
        cmd.commit()
    }

    private func renderToScaledTexture(cmd: MTLCommandBuffer, texture: MTLTexture, time: Float, lod: Float, uniformBuffer: MTLBuffer) {
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = texture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }

        enc.setRenderPipelineState(pipeline)

        let scaledSize = scaledRenderTarget.scaledSize
        let bufferPtr = uniformBuffer.contents()

        if usesRawMetalMode {
            var uniforms = RawMetalUniforms(
                resolution: SIMD2(Float(scaledSize.width), Float(scaledSize.height)),
                time: time,
                lod: lod
            )
            // Copy uniforms to pre-allocated buffer
            memcpy(bufferPtr, &uniforms, MemoryLayout<RawMetalUniforms>.stride)
            enc.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
            enc.setFragmentTexture(noiseTex, index: 0)
            enc.setFragmentSamplerState(sampler, index: 0)

            // Pass custom parameters in buffer (offset after uniforms)
            let parameterStore = theme.parameterStore
            let params = theme.manifest.parameters
            if !params.isEmpty {
                let paramOffset = Self.parameterBufferOffset
                let paramPtr = bufferPtr.advanced(by: paramOffset)
                for (i, param) in params.prefix(8).enumerated() {
                    let value = parameterStore.floatValue(for: param.id)
                    paramPtr.storeBytes(of: value, toByteOffset: i * MemoryLayout<Float>.stride, as: Float.self)
                }
                // Zero remaining slots
                for i in params.count..<8 {
                    paramPtr.storeBytes(of: Float(0), toByteOffset: i * MemoryLayout<Float>.stride, as: Float.self)
                }
                enc.setFragmentBuffer(uniformBuffer, offset: paramOffset, index: 1)
            }
        } else {
            var uniforms = StitchableUniforms(
                resolution: SIMD2(Float(scaledSize.width), Float(scaledSize.height)),
                time: time,
                displayScale: 1.0
            )
            // Copy uniforms to pre-allocated buffer
            memcpy(bufferPtr, &uniforms, MemoryLayout<StitchableUniforms>.stride)
            enc.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)

            // Pass custom parameters in buffer (offset after uniforms)
            let parameterStore = theme.parameterStore
            let params = theme.manifest.parameters
            if !params.isEmpty {
                let paramOffset = Self.parameterBufferOffset
                let paramPtr = bufferPtr.advanced(by: paramOffset)
                for (i, param) in params.prefix(8).enumerated() {
                    let value = parameterStore.floatValue(for: param.id)
                    paramPtr.storeBytes(of: value, toByteOffset: i * MemoryLayout<Float>.stride, as: Float.self)
                }
                // Zero remaining slots
                for i in params.count..<8 {
                    paramPtr.storeBytes(of: Float(0), toByteOffset: i * MemoryLayout<Float>.stride, as: Float.self)
                }
                enc.setFragmentBuffer(uniformBuffer, offset: paramOffset, index: 1)
            }
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

    private func renderDirectly(cmd: MTLCommandBuffer, descriptor: MTLRenderPassDescriptor, drawableSize: CGSize, time: Float, lod: Float, view: MTKView, uniformBuffer: MTLBuffer) {
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        enc.setRenderPipelineState(pipeline)

        let bufferPtr = uniformBuffer.contents()

        if usesRawMetalMode {
            var uniforms = RawMetalUniforms(
                resolution: SIMD2(Float(drawableSize.width), Float(drawableSize.height)),
                time: time,
                lod: lod
            )
            // Copy uniforms to pre-allocated buffer
            memcpy(bufferPtr, &uniforms, MemoryLayout<RawMetalUniforms>.stride)
            enc.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
            enc.setFragmentTexture(noiseTex, index: 0)
            enc.setFragmentSamplerState(sampler, index: 0)

            // Pass custom parameters in buffer (offset after uniforms)
            let parameterStore = theme.parameterStore
            let params = theme.manifest.parameters
            if !params.isEmpty {
                let paramOffset = Self.parameterBufferOffset
                let paramPtr = bufferPtr.advanced(by: paramOffset)
                for (i, param) in params.prefix(8).enumerated() {
                    let value = parameterStore.floatValue(for: param.id)
                    paramPtr.storeBytes(of: value, toByteOffset: i * MemoryLayout<Float>.stride, as: Float.self)
                }
                // Zero remaining slots
                for i in params.count..<8 {
                    paramPtr.storeBytes(of: Float(0), toByteOffset: i * MemoryLayout<Float>.stride, as: Float.self)
                }
                enc.setFragmentBuffer(uniformBuffer, offset: paramOffset, index: 1)
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
            // Copy uniforms to pre-allocated buffer
            memcpy(bufferPtr, &uniforms, MemoryLayout<StitchableUniforms>.stride)
            enc.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)

            // Pass custom parameters in buffer (offset after uniforms)
            let parameterStore = theme.parameterStore
            let params = theme.manifest.parameters
            if !params.isEmpty {
                let paramOffset = Self.parameterBufferOffset
                let paramPtr = bufferPtr.advanced(by: paramOffset)
                for (i, param) in params.prefix(8).enumerated() {
                    let value = parameterStore.floatValue(for: param.id)
                    paramPtr.storeBytes(of: value, toByteOffset: i * MemoryLayout<Float>.stride, as: Float.self)
                }
                // Zero remaining slots
                for i in params.count..<8 {
                    paramPtr.storeBytes(of: Float(0), toByteOffset: i * MemoryLayout<Float>.stride, as: Float.self)
                }
                enc.setFragmentBuffer(uniformBuffer, offset: paramOffset, index: 1)
            }
        }

        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    // MARK: - Frame Interpolation

    private func drawWithInterpolation(
        cmd: MTLCommandBuffer,
        drawable: CAMetalDrawable,
        view: MTKView,
        time: Float,
        displayTime: CFTimeInterval,
        shaderFPS: Float,
        resolutionScale: Float,
        lod: Float,
        uniformBuffer: MTLBuffer
    ) {
        guard let interpolationPipeline, let upscaleSampler else {
            // Fallback to non-interpolated rendering if pipeline not available
            if resolutionScale < 1.0, let scaledTexture = scaledRenderTarget.renderTexture {
                renderToScaledTexture(cmd: cmd, texture: scaledTexture, time: time, lod: lod, uniformBuffer: uniformBuffer)
                blitToDrawable(cmd: cmd, texture: scaledTexture, drawable: drawable, view: view)
            } else if let rpd = view.currentRenderPassDescriptor {
                renderDirectly(cmd: cmd, descriptor: rpd, drawableSize: view.drawableSize, time: time, lod: lod, view: view, uniformBuffer: uniformBuffer)
            }
            return
        }

        // Determine render size (apply resolution scaling to interpolation frames)
        let renderSize: CGSize
        if resolutionScale < 1.0 {
            renderSize = scaledRenderTarget.scaledSize
        } else {
            renderSize = view.drawableSize
        }

        // Update interpolator textures if needed
        _ = frameInterpolator.updateTextures(
            device: device,
            size: renderSize,
            pixelFormat: pixelFormat
        )

        // Update shader frame interval based on target shader FPS
        frameInterpolator.shaderFrameInterval = 1.0 / CFTimeInterval(shaderFPS)

        // Check if we need to render a new shader frame
        if frameInterpolator.shouldRenderShaderFrame(at: displayTime) {
            // Render shader to current frame texture
            if let targetTexture = frameInterpolator.currentFrame {
                renderToTexture(cmd: cmd, texture: targetTexture, size: renderSize, time: time, lod: lod, view: view, uniformBuffer: uniformBuffer)
            }
            // Swap frames and record timestamp
            frameInterpolator.recordShaderFrame(at: displayTime)
        }

        // Check if we have enough valid frames to blend
        if !frameInterpolator.isReady {
            // Not enough frames yet - display the latest valid frame directly, or render fresh
            if let latestFrame = frameInterpolator.latestValidFrame {
                // Blit the single valid frame to drawable
                blitToDrawable(cmd: cmd, texture: latestFrame, drawable: drawable, view: view)
            } else {
                // No valid frames at all - render directly to drawable
                if let rpd = view.currentRenderPassDescriptor {
                    renderDirectly(cmd: cmd, descriptor: rpd, drawableSize: view.drawableSize, time: time, lod: lod, view: view, uniformBuffer: uniformBuffer)
                }
            }
            return
        }

        // Blend previous and current frames to drawable
        guard
            let previousFrame = frameInterpolator.previousFrame,
            let currentFrame = frameInterpolator.currentFrame
        else {
            return
        }

        let blendFactor = frameInterpolator.blendFactor(at: displayTime)

        blendFramesToDrawable(
            cmd: cmd,
            previousFrame: previousFrame,
            currentFrame: currentFrame,
            blendFactor: blendFactor,
            drawable: drawable,
            pipeline: interpolationPipeline,
            sampler: upscaleSampler
        )
    }

    private func renderToTexture(
        cmd: MTLCommandBuffer,
        texture: MTLTexture,
        size: CGSize,
        time: Float,
        lod: Float,
        view: MTKView,
        uniformBuffer: MTLBuffer
    ) {
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = texture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }

        enc.setRenderPipelineState(pipeline)

        let bufferPtr = uniformBuffer.contents()

        if usesRawMetalMode {
            var uniforms = RawMetalUniforms(
                resolution: SIMD2(Float(size.width), Float(size.height)),
                time: time,
                lod: lod
            )
            memcpy(bufferPtr, &uniforms, MemoryLayout<RawMetalUniforms>.stride)
            enc.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
            enc.setFragmentTexture(noiseTex, index: 0)
            enc.setFragmentSamplerState(sampler, index: 0)

            setCustomParameters(encoder: enc, uniformBuffer: uniformBuffer, offset: Self.parameterBufferOffset)
        } else {
            #if os(iOS) || os(tvOS)
            let displayScale = Float(view.contentScaleFactor)
            #else
            let displayScale = Float(size.width / max(view.bounds.width, 1))
            #endif

            var uniforms = StitchableUniforms(
                resolution: SIMD2(Float(size.width), Float(size.height)),
                time: time,
                displayScale: displayScale
            )
            memcpy(bufferPtr, &uniforms, MemoryLayout<StitchableUniforms>.stride)
            enc.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)

            setCustomParameters(encoder: enc, uniformBuffer: uniformBuffer, offset: Self.parameterBufferOffset)
        }

        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    private func blendFramesToDrawable(
        cmd: MTLCommandBuffer,
        previousFrame: MTLTexture,
        currentFrame: MTLTexture,
        blendFactor: Float,
        drawable: CAMetalDrawable,
        pipeline: MTLRenderPipelineState,
        sampler: MTLSamplerState
    ) {
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = drawable.texture
        rpd.colorAttachments[0].loadAction = .dontCare
        rpd.colorAttachments[0].storeAction = .store

        guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }

        enc.setRenderPipelineState(pipeline)
        enc.setFragmentTexture(previousFrame, index: 0)
        enc.setFragmentTexture(currentFrame, index: 1)
        enc.setFragmentSamplerState(sampler, index: 0)

        var uniforms = InterpolationUniforms(blendFactor: blendFactor)
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<InterpolationUniforms>.stride, index: 0)

        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    /// Sets custom shader parameters on the encoder at buffer index 1.
    private func setCustomParameters(encoder: MTLRenderCommandEncoder, uniformBuffer: MTLBuffer, offset: Int) {
        let parameterStore = theme.parameterStore
        let params = theme.manifest.parameters
        guard !params.isEmpty else { return }

        let bufferPtr = uniformBuffer.contents()
        let paramPtr = bufferPtr.advanced(by: offset)

        for (i, param) in params.prefix(8).enumerated() {
            let value = parameterStore.floatValue(for: param.id)
            paramPtr.storeBytes(of: value, toByteOffset: i * MemoryLayout<Float>.stride, as: Float.self)
        }
        // Zero remaining slots
        for i in params.count..<8 {
            paramPtr.storeBytes(of: Float(0), toByteOffset: i * MemoryLayout<Float>.stride, as: Float.self)
        }

        encoder.setFragmentBuffer(uniformBuffer, offset: offset, index: 1)
    }

    // MARK: - Snapshot

    /// Captures a snapshot of the current wallpaper as a Core.Image.
    /// Renders a single frame to an offscreen texture and converts it to Core.Image.
    /// - Parameter size: The size of the snapshot (default 100x100 for color extraction).
    /// - Returns: A Core.Image (UIImage/NSImage) of the rendered wallpaper, or nil if rendering fails.
    public func captureSnapshot(size: CGSize = CGSize(width: 100, height: 100)) -> Core.Image? {
        guard let device, let queue, let pipeline else { return nil }

        // Create a texture descriptor for the snapshot
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: Int(size.width),
            height: Int(size.height),
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]

        guard let snapshotTexture = device.makeTexture(descriptor: descriptor) else { return nil }

        // Get uniform buffer
        guard !uniformBuffers.isEmpty else { return nil }
        let uniformBuffer = uniformBuffers[0]

        // Calculate time
        let now = CACurrentMediaTime()
        let timeScale = theme.manifest.renderer.timeScale ?? 1.0
        let time = Float(now - startTime) * timeScale

        // Create render pass descriptor
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = snapshotTexture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else { return nil }

        encoder.setRenderPipelineState(pipeline)

        let bufferPtr = uniformBuffer.contents()

        if usesRawMetalMode {
            var uniforms = RawMetalUniforms(
                resolution: SIMD2(Float(size.width), Float(size.height)),
                time: time,
                lod: 1.0
            )
            memcpy(bufferPtr, &uniforms, MemoryLayout<RawMetalUniforms>.size)
            encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)

            if let sampler { encoder.setFragmentSamplerState(sampler, index: 0) }
            if let noiseTex { encoder.setFragmentTexture(noiseTex, index: 0) }

            setCustomParameters(
                encoder: encoder,
                uniformBuffer: uniformBuffer,
                offset: Self.parameterBufferOffset
            )
        } else {
            var uniforms = StitchableUniforms(
                resolution: SIMD2(Float(size.width), Float(size.height)),
                time: time,
                displayScale: 1.0
            )
            memcpy(bufferPtr, &uniforms, MemoryLayout<StitchableUniforms>.size)
            encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)

            setCustomParameters(
                encoder: encoder,
                uniformBuffer: uniformBuffer,
                offset: MemoryLayout<StitchableUniforms>.stride
            )
        }

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // Convert texture to Image
        return textureToImage(snapshotTexture)
    }

    /// Converts an MTLTexture to a Core.Image (UIImage/NSImage).
    private func textureToImage(_ texture: MTLTexture) -> Core.Image? {
        let width = texture.width
        let height = texture.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let byteCount = bytesPerRow * height

        var bytes = [UInt8](repeating: 0, count: byteCount)
        texture.getBytes(
            &bytes,
            bytesPerRow: bytesPerRow,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )

        // Create CGImage from bytes
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
            .union(.byteOrder32Little)

        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ),
        let cgImage = context.makeImage() else {
            return nil
        }

        #if os(iOS) || os(tvOS)
        return UIImage(cgImage: cgImage)
        #elseif os(macOS)
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        #endif
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
