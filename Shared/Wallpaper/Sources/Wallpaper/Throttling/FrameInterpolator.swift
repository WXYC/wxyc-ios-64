//
//  FrameInterpolator.swift
//  Wallpaper
//
//  Interpolates frames for smooth throttled rendering.
//
//  Created by Jake Bromberg on 01/09/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Metal

/// Manages frame caching and interpolation for thermal throttling.
///
/// When enabled, this allows the renderer to execute the shader at a lower rate
/// (e.g., 30 fps) while displaying at a higher rate (e.g., 60 fps) by blending
/// between cached frames. This reduces GPU shader workload while maintaining
/// perceived smoothness.
///
/// ## How It Works
///
/// 1. Every N display frames, the shader executes and renders to a frame texture
/// 2. The previous shader output is stored for blending
/// 3. On intermediate display frames, we blend between previous and current
///    based on the sub-frame time
///
/// ## Important: Valid Frame Tracking
///
/// The interpolator tracks how many frames have been rendered since the last
/// reset (due to texture recreation, app resuming, etc.). Blending is only
/// safe when at least 2 valid frames exist. Before that, the single valid
/// frame is displayed directly without blending.
struct FrameInterpolator {

    /// The previous rendered frame.
    private(set) var previousFrame: MTLTexture?

    /// The current rendered frame.
    private(set) var currentFrame: MTLTexture?

    /// Timestamp of the previous shader execution.
    private var previousFrameTime: CFTimeInterval?

    /// Timestamp of the current shader execution.
    private var currentFrameTime: CFTimeInterval?

    /// Number of valid frames rendered since last reset.
    ///
    /// We need at least 2 valid frames before we can safely blend.
    /// After texture recreation, this resets to 0.
    private var validFrameCount: Int = 0

    /// Current texture size.
    private var currentSize: CGSize = .zero

    /// Current pixel format.
    private var currentPixelFormat: MTLPixelFormat = .bgra8Unorm

    /// The interval between shader executions (inverse of shader FPS).
    var shaderFrameInterval: CFTimeInterval = 1.0 / 30.0

    /// Maximum time gap before considering frames stale.
    ///
    /// If the gap between frames exceeds this (e.g., app was backgrounded),
    /// we reset and require fresh frames before blending.
    private let maxFrameGap: CFTimeInterval = 1.0

    /// Number of times the interpolator has been reset since creation.
    ///
    /// Useful for analytics to track potential visual glitches.
    /// High reset counts during normal use may indicate issues.
    private(set) var resetCount: Int = 0

    /// Whether interpolation is ready (has enough valid frames to blend).
    var isReady: Bool {
        validFrameCount >= 2
    }

    /// The texture containing the most recently rendered valid frame.
    ///
    /// Use this for direct display when interpolation isn't ready yet.
    var latestValidFrame: MTLTexture? {
        // After recordShaderFrame, previousFrame holds the just-rendered content
        // currentFrame is the target for the next render
        if validFrameCount >= 1 {
            return previousFrame
        }
        return nil
    }

    /// Whether a new shader frame should be rendered this display frame.
    ///
    /// - Parameter displayTime: The current display timestamp (CACurrentMediaTime).
    /// - Returns: `true` if enough time has passed to render a new shader frame.
    func shouldRenderShaderFrame(at displayTime: CFTimeInterval) -> Bool {
        // Always render if we don't have enough valid frames yet
        guard validFrameCount >= 2, let currentTime = currentFrameTime else {
            return true
        }

        // Check for stale frames (app was backgrounded for a long time)
        let elapsed = displayTime - currentTime
        if elapsed > maxFrameGap {
            return true
        }

        return elapsed >= shaderFrameInterval
    }

    /// Computes the blend factor for interpolation between frames.
    ///
    /// - Parameter displayTime: The current display timestamp.
    /// - Returns: A value from 0.0 (show previous frame) to 1.0 (show current frame).
    func blendFactor(at displayTime: CFTimeInterval) -> Float {
        guard let prevTime = previousFrameTime,
              let currTime = currentFrameTime,
              currTime > prevTime else {
            return 1.0
        }

        let frameDuration = currTime - prevTime
        guard frameDuration > 0 else { return 1.0 }

        let elapsed = displayTime - prevTime
        let t = elapsed / frameDuration

        // Clamp to [0, 1]
        return Float(min(max(t, 0), 1))
    }

    /// Updates the frame textures if size or format changed.
    ///
    /// - Parameters:
    ///   - device: Metal device for texture creation.
    ///   - size: The texture size in pixels.
    ///   - pixelFormat: The pixel format.
    /// - Returns: `true` if textures were recreated.
    mutating func updateTextures(
        device: MTLDevice,
        size: CGSize,
        pixelFormat: MTLPixelFormat
    ) -> Bool {
        guard size != currentSize || pixelFormat != currentPixelFormat else {
            return false
        }

        currentSize = size
        currentPixelFormat = pixelFormat

        let width = Int(size.width)
        let height = Int(size.height)

        guard width > 0, height > 0 else {
            previousFrame = nil
            currentFrame = nil
            reset()
            return true
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private

        previousFrame = device.makeTexture(descriptor: descriptor)
        currentFrame = device.makeTexture(descriptor: descriptor)

        // Reset state when textures change - we need fresh frames
        reset()

        return true
    }

    /// Records that a new shader frame was rendered to `currentFrame`.
    ///
    /// Call this after rendering to `currentFrame`. This swaps the frame
    /// references and updates timestamps.
    ///
    /// - Parameter time: The timestamp when the shader frame was rendered.
    /// - Returns: `true` if a stale frame reset occurred.
    @discardableResult
    mutating func recordShaderFrame(at time: CFTimeInterval) -> Bool {
        // Check for stale frames before recording
        var didReset = false
        if let lastTime = currentFrameTime, time - lastTime > maxFrameGap {
            // Too much time has passed - reset and start fresh
            reset()
            didReset = true
        }

        // Swap frames: current becomes previous
        swap(&previousFrame, &currentFrame)

        previousFrameTime = currentFrameTime
        currentFrameTime = time

        // Increment valid frame count (capped at 2, we only need to know >= 2)
        validFrameCount = min(validFrameCount + 1, 2)

        return didReset
    }

    /// Resets the interpolator state.
    ///
    /// Call this when the shader changes, the view reappears, or the app
    /// returns from background.
    mutating func reset() {
        previousFrameTime = nil
        currentFrameTime = nil
        validFrameCount = 0
        resetCount += 1
    }

    /// Resets the reset counter.
    ///
    /// Call this when starting a new analytics session.
    mutating func resetAnalytics() {
        resetCount = 0
    }
}
