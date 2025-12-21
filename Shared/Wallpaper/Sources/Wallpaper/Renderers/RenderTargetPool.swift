//
//  RenderTargetPool.swift
//  Wallpaper
//
//  Created by Claude on 12/20/25.
//

import Metal
import Foundation

/// Manages render target textures for multi-pass rendering.
/// Handles texture allocation, double-buffering for feedback loops, and resolution scaling.
final class RenderTargetPool {
    private let device: MTLDevice
    private var textures: [String: [MTLTexture]] = [:]
    private var pingPongIndex: [String: Int] = [:]
    private var currentResolution: CGSize = .zero
    private var currentScale: CGFloat = 1.0

    init(device: MTLDevice) {
        self.device = device
    }

    /// Configures render targets for the given passes.
    /// - Parameters:
    ///   - passes: The pass configurations from the manifest
    ///   - resolution: The base resolution (e.g., drawable size)
    ///   - scale: Display scale factor
    func configure(passes: [PassConfiguration], resolution: CGSize, scale: CGFloat) {
        // Skip reconfiguration if resolution hasn't changed
        guard resolution != currentResolution || scale != currentScale else { return }

        currentResolution = resolution
        currentScale = scale

        // Analyze which passes need feedback (double-buffering)
        let feedbackPasses = determineFeedbackPasses(passes: passes)

        // Create or recreate textures for each non-final pass
        for (index, pass) in passes.enumerated() {
            // Skip the final pass - it renders directly to drawable
            guard index < passes.count - 1 else { continue }

            let passScale = CGFloat(pass.effectiveScale)
            let width = Int(resolution.width * passScale)
            let height = Int(resolution.height * passScale)

            let needsDoubleBuffer = feedbackPasses.contains(pass.name)
            let bufferCount = needsDoubleBuffer ? 2 : 1

            // Create textures
            var passTextures: [MTLTexture] = []
            for _ in 0..<bufferCount {
                if let texture = createTexture(width: width, height: height) {
                    passTextures.append(texture)
                }
            }

            textures[pass.name] = passTextures
            pingPongIndex[pass.name] = 0
        }
    }

    /// Returns the current output texture for a pass.
    func getOutputTexture(for passName: String) -> MTLTexture? {
        guard let passTextures = textures[passName], !passTextures.isEmpty else { return nil }
        let index = pingPongIndex[passName] ?? 0
        return passTextures[index % passTextures.count]
    }

    /// Returns the previous frame texture for feedback passes.
    func getPreviousTexture(for passName: String) -> MTLTexture? {
        guard let passTextures = textures[passName], passTextures.count > 1 else { return nil }
        let index = pingPongIndex[passName] ?? 0
        return passTextures[(index + 1) % passTextures.count]
    }

    /// Swaps the ping-pong buffer index for feedback passes.
    func swapBuffers(for passName: String) {
        guard let passTextures = textures[passName], passTextures.count > 1 else { return }
        let currentIndex = pingPongIndex[passName] ?? 0
        pingPongIndex[passName] = (currentIndex + 1) % passTextures.count
    }

    /// Resolves an input source to a texture.
    /// - Parameters:
    ///   - source: The source identifier (pass name, "previousFrame", or "noise")
    ///   - currentPassName: The name of the pass requesting the input
    ///   - noiseTexture: Optional noise texture for "noise" source
    func resolveInput(source: String, currentPassName: String, noiseTexture: MTLTexture?) -> MTLTexture? {
        switch source {
        case PassInput.previousFrame:
            return getPreviousTexture(for: currentPassName)
        case PassInput.noise:
            return noiseTexture
        default:
            // Reference to another pass's output
            return getOutputTexture(for: source)
        }
    }

    // MARK: - Private

    private func createTexture(width: Int, height: Int) -> MTLTexture? {
        guard width > 0, height > 0 else { return nil }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        #if os(iOS) || os(tvOS)
        descriptor.storageMode = .shared  // Required for iOS
        #else
        descriptor.storageMode = .private // GPU-only for macOS
        #endif

        return device.makeTexture(descriptor: descriptor)
    }

    private func determineFeedbackPasses(passes: [PassConfiguration]) -> Set<String> {
        var feedbackPasses = Set<String>()

        for pass in passes {
            guard let inputs = pass.inputs else { continue }
            for input in inputs {
                if input.source == PassInput.previousFrame {
                    feedbackPasses.insert(pass.name)
                    break
                }
            }
        }

        return feedbackPasses
    }

    /// Clears all textures and resets state.
    func reset() {
        textures.removeAll()
        pingPongIndex.removeAll()
        currentResolution = .zero
        currentScale = 1.0
    }
}
