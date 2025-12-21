//
//  MultiPassMetalRenderer.swift
//  Wallpaper
//
//  Created by Claude on 12/20/25.
//

import MetalKit
import simd

/// MTKViewDelegate implementation for rendering multi-pass shaders via Metal.
/// Supports intermediate render targets, feedback loops, and post-processing chains.
public final class MultiPassMetalRenderer: NSObject, MTKViewDelegate {
    /// Uniforms struct matching the Metal side.
    struct Uniforms {
        var resolution: SIMD2<Float>
        var time: Float
        var displayScale: Float
        var frame: Int32
        var passIndex: Int32
        // Audio data
        var audioLevel: Float
        var audioBass: Float
        var audioMid: Float
        var audioHigh: Float
        var audioBeat: Float
        var pad: Float = 0
    }

    private var device: MTLDevice!
    private var queue: MTLCommandQueue!
    private var pipelines: [String: MTLRenderPipelineState] = [:]
    private var sampler: MTLSamplerState!
    private var noiseTexture: MTLTexture?
    private var targetPool: RenderTargetPool!

    private var startTime = CACurrentMediaTime()
    private var frameCount: Int32 = 0
    private let wallpaper: LoadedWallpaper
    private var audioData: AudioData?

    init(wallpaper: LoadedWallpaper) {
        self.wallpaper = wallpaper
        super.init()
    }

    func updateAudioData(_ audioData: AudioData?) {
        self.audioData = audioData
    }

    func configure(view: MTKView) {
        guard let device = view.device else { return }
        self.device = device
        self.queue = device.makeCommandQueue()
        self.targetPool = RenderTargetPool(device: device)

        let renderer = wallpaper.manifest.renderer
        guard let passes = renderer.passes, !passes.isEmpty else {
            print("MultiPassMetalRenderer: No passes configured")
            return
        }

        // Load Metal library from package bundle
        guard let library = try? device.makeDefaultLibrary(bundle: Bundle.module) else {
            print("MultiPassMetalRenderer: Failed to load Metal library from bundle")
            return
        }

        // Vertex function is always fullscreenVertex
        guard let vertexFn = library.makeFunction(name: "fullscreenVertex") else {
            print("MultiPassMetalRenderer: Vertex function 'fullscreenVertex' not found")
            return
        }

        // Create a pipeline for each pass
        for pass in passes {
            guard let fragmentFn = library.makeFunction(name: pass.fragmentFunction) else {
                print("MultiPassMetalRenderer: Fragment function '\(pass.fragmentFunction)' not found")
                continue
            }

            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vertexFn
            desc.fragmentFunction = fragmentFn
            desc.colorAttachments[0].pixelFormat = view.colorPixelFormat

            do {
                let pipeline = try device.makeRenderPipelineState(descriptor: desc)
                pipelines[pass.name] = pipeline
            } catch {
                print("MultiPassMetalRenderer: Failed to create pipeline for '\(pass.name)': \(error)")
            }
        }

        // Create sampler for texture sampling
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .repeat
        samplerDesc.tAddressMode = .repeat
        sampler = device.makeSamplerState(descriptor: samplerDesc)

        // Create noise texture if needed
        createNoiseTexture()
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Reconfigure render targets when size changes
        guard let passes = wallpaper.manifest.renderer.passes else { return }
        #if os(iOS) || os(tvOS)
        let scale = view.contentScaleFactor
        #else
        let scale = view.drawableSize.width / max(view.bounds.width, 1)
        #endif
        targetPool.configure(passes: passes, resolution: size, scale: scale)
    }

    public func draw(in view: MTKView) {
        guard
            let queue,
            let drawable = view.currentDrawable
        else { return }

        let passes = wallpaper.manifest.renderer.passes ?? []
        guard !passes.isEmpty else { return }

        // Ensure render targets are configured
        #if os(iOS) || os(tvOS)
        let viewScale = view.contentScaleFactor
        #else
        let viewScale = view.drawableSize.width / max(view.bounds.width, 1)
        #endif
        targetPool.configure(
            passes: passes,
            resolution: view.drawableSize,
            scale: viewScale
        )

        let now = CACurrentMediaTime()
        let timeScale = wallpaper.manifest.renderer.timeScale ?? 1.0
        let t = Float(now - startTime) * timeScale

        #if os(iOS) || os(tvOS)
        let scale = Float(view.contentScaleFactor)
        #else
        let scale = Float(view.drawableSize.width / max(view.bounds.width, 1))
        #endif

        guard let cmd = queue.makeCommandBuffer() else { return }

        // Render each pass
        for (index, pass) in passes.enumerated() {
            let isLastPass = (index == passes.count - 1)

            // Get pipeline for this pass
            guard let pipeline = pipelines[pass.name] else {
                print("MultiPassMetalRenderer: No pipeline for pass '\(pass.name)'")
                continue
            }

            // Determine output texture or drawable
            let descriptor: MTLRenderPassDescriptor
            let passResolution: SIMD2<Float>

            if isLastPass {
                guard let rpd = view.currentRenderPassDescriptor else { continue }
                descriptor = rpd
                passResolution = SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height))
            } else {
                guard let outputTexture = targetPool.getOutputTexture(for: pass.name) else {
                    print("MultiPassMetalRenderer: No output texture for pass '\(pass.name)'")
                    continue
                }
                descriptor = makeOffscreenDescriptor(target: outputTexture)
                passResolution = SIMD2(Float(outputTexture.width), Float(outputTexture.height))
            }

            // Create uniforms for this pass
            var uniforms = Uniforms(
                resolution: passResolution,
                time: t,
                displayScale: scale,
                frame: frameCount,
                passIndex: Int32(index),
                audioLevel: audioData?.level ?? 0,
                audioBass: audioData?.bass ?? 0,
                audioMid: audioData?.mid ?? 0,
                audioHigh: audioData?.high ?? 0,
                audioBeat: audioData?.beat ?? 0
            )

            guard let enc = cmd.makeRenderCommandEncoder(descriptor: descriptor) else { continue }

            enc.setRenderPipelineState(pipeline)
            enc.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)

            // Bind input textures
            if let inputs = pass.inputs {
                for input in inputs {
                    if let texture = targetPool.resolveInput(
                        source: input.source,
                        currentPassName: pass.name,
                        noiseTexture: noiseTexture
                    ) {
                        enc.setFragmentTexture(texture, index: input.channel)
                    }
                }
            }

            // Bind sampler
            enc.setFragmentSamplerState(sampler, index: 0)

            // Fullscreen triangle
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()

            // Swap feedback buffers after rendering
            if passUsesFeedback(pass) {
                targetPool.swapBuffers(for: pass.name)
            }
        }

        cmd.present(drawable)
        cmd.commit()

        frameCount += 1
    }

    // MARK: - Private

    private func makeOffscreenDescriptor(target: MTLTexture) -> MTLRenderPassDescriptor {
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = target
        desc.colorAttachments[0].loadAction = .clear
        desc.colorAttachments[0].storeAction = .store
        desc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        return desc
    }

    private func passUsesFeedback(_ pass: PassConfiguration) -> Bool {
        guard let inputs = pass.inputs else { return false }
        return inputs.contains { $0.source == PassInput.previousFrame }
    }

    private func createNoiseTexture() {
        let size = 256
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: size,
            height: size,
            mipmapped: false
        )
        descriptor.usage = .shaderRead

        guard let texture = device.makeTexture(descriptor: descriptor) else { return }

        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = UInt8.random(in: 0...255)     // R
            pixels[i + 1] = UInt8.random(in: 0...255) // G
            pixels[i + 2] = UInt8.random(in: 0...255) // B
            pixels[i + 3] = 255                        // A
        }

        texture.replace(
            region: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: size * 4
        )

        noiseTexture = texture
    }
}
