//
//  ComputePipelineManager.swift
//  Wallpaper
//
//  Manages compute shader pipelines and persistent textures for compute-based wallpapers.
//

import Metal
import MetalKit

/// Manages compute pipeline state and persistent textures for compute-based wallpapers.
final class ComputePipelineManager {

    // MARK: - Types

    struct ComputePass {
        let name: String
        let pipeline: MTLComputePipelineState
        let threadGroupSize: MTLSize
        let inputs: [ComputeTextureBinding]
        let outputs: [ComputeTextureBinding]
    }

    struct PersistentTexture {
        let name: String
        var textures: [MTLTexture]  // 1 for single-buffered, 2 for double-buffered
        var currentIndex: Int = 0
        let isDoubleBuffered: Bool

        var current: MTLTexture { textures[currentIndex] }
        var previous: MTLTexture { textures[isDoubleBuffered ? 1 - currentIndex : currentIndex] }

        mutating func swap() {
            if isDoubleBuffered {
                currentIndex = 1 - currentIndex
            }
        }
    }

    // MARK: - Properties

    private let device: MTLDevice
    private var computePasses: [ComputePass] = []
    private var persistentTextures: [String: PersistentTexture] = [:]
    private var renderPipeline: MTLRenderPipelineState?
    private var currentSize: CGSize = .zero

    /// Whether the compute pipeline is ready to use.
    var isReady: Bool {
        !computePasses.isEmpty && renderPipeline != nil
    }

    // MARK: - Initialization

    init(device: MTLDevice) {
        self.device = device
    }

    // MARK: - Setup

    /// Sets up compute pipelines from configuration.
    /// - Parameters:
    ///   - config: The compute configuration from the theme manifest.
    ///   - library: The Metal library containing the compute functions.
    ///   - pixelFormat: The pixel format for the render pipeline.
    func setUp(
        config: ComputeConfiguration,
        library: MTLLibrary,
        pixelFormat: MTLPixelFormat
    ) throws {
        // Create compute pipelines for each pass
        computePasses = try config.passes.map { passConfig in
            guard let function = library.makeFunction(name: passConfig.functionName) else {
                throw ComputeError.functionNotFound(passConfig.functionName)
            }

            let pipeline = try device.makeComputePipelineState(function: function)
            let (x, y, z) = passConfig.effectiveThreadGroupSize

            return ComputePass(
                name: passConfig.name,
                pipeline: pipeline,
                threadGroupSize: MTLSize(width: x, height: y, depth: z),
                inputs: passConfig.inputs ?? [],
                outputs: passConfig.outputs ?? []
            )
        }

        // Create render pipeline for final output
        guard let vertexFunction = library.makeFunction(name: "fullscreenVertex"),
              let fragmentFunction = library.makeFunction(name: config.renderFunction) else {
            throw ComputeError.functionNotFound(config.renderFunction)
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = pixelFormat

        renderPipeline = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }

    /// Sets up persistent textures based on configuration and current view size.
    func setUpPersistentTextures(
        configs: [PersistentTextureConfiguration]?,
        size: CGSize
    ) {
        guard let configs = configs, size != currentSize else { return }
        currentSize = size

        for config in configs {
            let scaledWidth = Int(size.width * CGFloat(config.effectiveScale))
            let scaledHeight = Int(size.height * CGFloat(config.effectiveScale))

            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: pixelFormat(for: config.format),
                width: max(1, scaledWidth),
                height: max(1, scaledHeight),
                mipmapped: false
            )
            descriptor.usage = [.shaderRead, .shaderWrite]
            descriptor.storageMode = .private

            let textureCount = config.isDoubleBuffered ? 2 : 1
            var textures: [MTLTexture] = []

            for _ in 0..<textureCount {
                if let texture = device.makeTexture(descriptor: descriptor) {
                    textures.append(texture)
                }
            }

            if !textures.isEmpty {
                persistentTextures[config.name] = PersistentTexture(
                    name: config.name,
                    textures: textures,
                    isDoubleBuffered: config.isDoubleBuffered
                )
            }
        }
    }

    // MARK: - Execution

    /// Executes all compute passes.
    /// - Parameters:
    ///   - commandBuffer: The command buffer to encode into.
    ///   - uniforms: Uniform buffer containing time, resolution, etc.
    ///   - size: The current view size for dispatch calculation.
    func executeComputePasses(
        commandBuffer: MTLCommandBuffer,
        uniforms: MTLBuffer,
        size: CGSize
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }

        for pass in computePasses {
            encoder.setComputePipelineState(pass.pipeline)
            encoder.setBuffer(uniforms, offset: 0, index: 0)

            // Bind input textures
            for binding in pass.inputs {
                if let texture = texture(for: binding.source) {
                    encoder.setTexture(texture, index: binding.index)
                }
            }

            // Bind output textures
            for binding in pass.outputs {
                if let texture = texture(for: binding.source) {
                    encoder.setTexture(texture, index: binding.index)
                }
            }

            // Calculate dispatch size
            let threadGroupSize = pass.threadGroupSize
            let threadgroupsPerGrid = MTLSize(
                width: (Int(size.width) + threadGroupSize.width - 1) / threadGroupSize.width,
                height: (Int(size.height) + threadGroupSize.height - 1) / threadGroupSize.height,
                depth: 1
            )

            encoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadGroupSize)
        }

        encoder.endEncoding()

        // Swap double-buffered textures after all passes complete
        for key in persistentTextures.keys {
            persistentTextures[key]?.swap()
        }
    }

    /// Renders the final output to a render pass descriptor.
    func render(
        commandBuffer: MTLCommandBuffer,
        renderPassDescriptor: MTLRenderPassDescriptor,
        uniforms: MTLBuffer,
        sampler: MTLSamplerState?
    ) {
        guard let pipeline = renderPipeline,
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBuffer(uniforms, offset: 0, index: 0)

        // Bind trail map or other persistent textures for rendering
        if let trailMap = persistentTextures[ComputeTextureBinding.trailMap]?.current {
            encoder.setFragmentTexture(trailMap, index: 0)
        }

        if let sampler = sampler {
            encoder.setFragmentSamplerState(sampler, index: 0)
        }

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    // MARK: - Helpers

    private func texture(for source: String) -> MTLTexture? {
        persistentTextures[source]?.current
    }

    private func pixelFormat(for formatString: String) -> MTLPixelFormat {
        switch formatString.lowercased() {
        case "r8unorm", "r8":
            return .r8Unorm
        case "rg16float", "rg16f":
            return .rg16Float
        case "rgba16float", "rgba16f":
            return .rgba16Float
        case "r32uint":
            return .r32Uint
        case "rgba8unorm", "rgba8":
            return .rgba8Unorm
        case "bgra8unorm", "bgra8":
            return .bgra8Unorm
        default:
            return .rgba8Unorm
        }
    }

    // MARK: - Errors

    enum ComputeError: LocalizedError {
        case functionNotFound(String)
        case pipelineCreationFailed(String)

        var errorDescription: String? {
            switch self {
            case .functionNotFound(let name):
                return "Compute function '\(name)' not found"
            case .pipelineCreationFailed(let reason):
                return "Failed to create compute pipeline: \(reason)"
            }
        }
    }
}
