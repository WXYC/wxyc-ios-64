//
//  FrameInterpolatorTests.swift
//  Wallpaper
//
//  Tests for FrameInterpolator smoothing.
//
//  Created by Jake Bromberg on 01/09/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Metal
import QuartzCore
import Testing
@testable import Wallpaper

@Suite("FrameInterpolator")
struct FrameInterpolatorTests {

    // MARK: - Initial State

    @Test("Initial state is not ready for interpolation")
    func initialStateNotReady() {
        let interpolator = FrameInterpolator()
        #expect(!interpolator.isReady)
        #expect(interpolator.latestValidFrame == nil)
        #expect(interpolator.previousFrame == nil)
        #expect(interpolator.currentFrame == nil)
    }

    @Test("Should render shader frame when no frames exist")
    func shouldRenderWhenNoFrames() {
        let interpolator = FrameInterpolator()
        let now = CACurrentMediaTime()
        #expect(interpolator.shouldRenderShaderFrame(at: now))
    }

    // MARK: - Valid Frame Tracking

    @Test("Not ready after only one frame rendered")
    func notReadyAfterOneFrame() {
        var interpolator = FrameInterpolator()
        let now = CACurrentMediaTime()

        // Record one frame
        interpolator.recordShaderFrame(at: now)

        // Should still not be ready for blending
        #expect(!interpolator.isReady)
    }

    @Test("Ready after two frames rendered")
    func readyAfterTwoFrames() {
        var interpolator = FrameInterpolator()
        var time = CACurrentMediaTime()

        // Record first frame
        interpolator.recordShaderFrame(at: time)
        #expect(!interpolator.isReady)

        // Record second frame
        time += 0.033 // ~30fps
        interpolator.recordShaderFrame(at: time)

        // Now should be ready
        #expect(interpolator.isReady)
    }

    @Test("Latest valid frame available after first render")
    func latestValidFrameAfterFirstRender() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return // Skip if Metal not available
        }

        var interpolator = FrameInterpolator()
        let size = CGSize(width: 100, height: 100)

        // Create textures
        _ = interpolator.updateTextures(device: device, size: size, pixelFormat: .bgra8Unorm)

        // Initially no valid frame
        #expect(interpolator.latestValidFrame == nil)

        // Record a frame
        interpolator.recordShaderFrame(at: CACurrentMediaTime())

        // Now latestValidFrame should be available
        #expect(interpolator.latestValidFrame != nil)
    }

    // MARK: - Blend Factor

    @Test("Blend factor is 1.0 when no previous frame time")
    func blendFactorWithoutPreviousTime() {
        var interpolator = FrameInterpolator()
        let now = CACurrentMediaTime()

        // Only one frame recorded - previousFrameTime is nil
        interpolator.recordShaderFrame(at: now)

        let blendFactor = interpolator.blendFactor(at: now + 0.016)
        #expect(blendFactor == 1.0)
    }

    @Test("Blend factor interpolates correctly between frames")
    func blendFactorInterpolation() {
        var interpolator = FrameInterpolator()
        var time: CFTimeInterval = 1000.0 // Arbitrary base time

        // Record first frame
        interpolator.recordShaderFrame(at: time)

        // Record second frame 0.033s later (30fps)
        time += 0.033
        interpolator.recordShaderFrame(at: time)

        // At current frame time, blend should be 1.0
        #expect(interpolator.blendFactor(at: time) == 1.0)

        // Halfway between frames
        let midpoint = time - 0.033 / 2
        let midBlend = interpolator.blendFactor(at: midpoint)
        #expect(midBlend > 0.4 && midBlend < 0.6)

        // At previous frame time, blend should be 0.0
        let atPrevious = interpolator.blendFactor(at: time - 0.033)
        #expect(atPrevious < 0.1)
    }

    @Test("Blend factor is clamped to [0, 1]")
    func blendFactorClamping() {
        var interpolator = FrameInterpolator()
        var time: CFTimeInterval = 1000.0

        interpolator.recordShaderFrame(at: time)
        time += 0.033
        interpolator.recordShaderFrame(at: time)

        // Way before previous frame
        let veryEarly = interpolator.blendFactor(at: time - 1.0)
        #expect(veryEarly >= 0.0)

        // Way after current frame
        let veryLate = interpolator.blendFactor(at: time + 1.0)
        #expect(veryLate <= 1.0)
    }

    // MARK: - Should Render Shader Frame

    @Test("Should render when enough time has passed")
    func shouldRenderAfterInterval() {
        var interpolator = FrameInterpolator()
        interpolator.shaderFrameInterval = 0.033 // 30fps

        var time: CFTimeInterval = 1000.0

        // Record two frames to become ready
        interpolator.recordShaderFrame(at: time)
        time += 0.033
        interpolator.recordShaderFrame(at: time)

        // Should not render immediately
        #expect(!interpolator.shouldRenderShaderFrame(at: time + 0.001))

        // Should render after interval passes
        #expect(interpolator.shouldRenderShaderFrame(at: time + 0.034))
    }

    @Test("Should always render when not ready")
    func shouldAlwaysRenderWhenNotReady() {
        var interpolator = FrameInterpolator()
        interpolator.shaderFrameInterval = 0.033

        let time: CFTimeInterval = 1000.0

        // Only one frame - not ready yet
        interpolator.recordShaderFrame(at: time)
        #expect(!interpolator.isReady)

        // Should render even if interval hasn't passed
        #expect(interpolator.shouldRenderShaderFrame(at: time + 0.001))
    }

    // MARK: - Stale Frame Detection

    @Test("Detects stale frames after long gap")
    func detectsStaleFrames() {
        var interpolator = FrameInterpolator()
        var time: CFTimeInterval = 1000.0

        // Record two frames to become ready
        interpolator.recordShaderFrame(at: time)
        time += 0.033
        interpolator.recordShaderFrame(at: time)
        #expect(interpolator.isReady)

        // After a very long gap (simulating app background), should require new frames
        // The shouldRenderShaderFrame should return true due to stale detection
        #expect(interpolator.shouldRenderShaderFrame(at: time + 2.0))
    }

    @Test("Resets valid frame count after stale detection on record")
    func resetsAfterStaleGap() {
        var interpolator = FrameInterpolator()
        var time: CFTimeInterval = 1000.0

        // Build up to ready state
        interpolator.recordShaderFrame(at: time)
        time += 0.033
        interpolator.recordShaderFrame(at: time)
        #expect(interpolator.isReady)

        // Record after a very long gap - this should reset
        time += 2.0 // More than maxFrameGap (1.0)
        interpolator.recordShaderFrame(at: time)

        // Should no longer be ready - need to build up frames again
        #expect(!interpolator.isReady)
    }

    // MARK: - Texture Management

    @Test("Creates textures with correct size")
    func createsTexturesWithCorrectSize() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return // Skip if Metal not available
        }

        var interpolator = FrameInterpolator()
        let size = CGSize(width: 200, height: 300)

        let recreated = interpolator.updateTextures(device: device, size: size, pixelFormat: .bgra8Unorm)
        #expect(recreated)

        #expect(interpolator.previousFrame?.width == 200)
        #expect(interpolator.previousFrame?.height == 300)
        #expect(interpolator.currentFrame?.width == 200)
        #expect(interpolator.currentFrame?.height == 300)
    }

    @Test("Does not recreate textures when size unchanged")
    func doesNotRecreateTexturesWhenSizeUnchanged() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return // Skip if Metal not available
        }

        var interpolator = FrameInterpolator()
        let size = CGSize(width: 100, height: 100)

        let firstRecreate = interpolator.updateTextures(device: device, size: size, pixelFormat: .bgra8Unorm)
        #expect(firstRecreate)

        let secondRecreate = interpolator.updateTextures(device: device, size: size, pixelFormat: .bgra8Unorm)
        #expect(!secondRecreate)
    }

    @Test("Resets state when textures recreated")
    func resetsStateWhenTexturesRecreated() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return // Skip if Metal not available
        }

        var interpolator = FrameInterpolator()
        let size = CGSize(width: 100, height: 100)

        _ = interpolator.updateTextures(device: device, size: size, pixelFormat: .bgra8Unorm)

        // Build up to ready state
        var time: CFTimeInterval = 1000.0
        interpolator.recordShaderFrame(at: time)
        time += 0.033
        interpolator.recordShaderFrame(at: time)
        #expect(interpolator.isReady)

        // Recreate textures with different size
        let newSize = CGSize(width: 200, height: 200)
        _ = interpolator.updateTextures(device: device, size: newSize, pixelFormat: .bgra8Unorm)

        // Should no longer be ready
        #expect(!interpolator.isReady)
    }

    // MARK: - Reset

    @Test("Reset clears all state")
    func resetClearsState() {
        var interpolator = FrameInterpolator()
        var time: CFTimeInterval = 1000.0

        // Build up to ready state
        interpolator.recordShaderFrame(at: time)
        time += 0.033
        interpolator.recordShaderFrame(at: time)
        #expect(interpolator.isReady)

        // Reset
        interpolator.reset()

        // Should no longer be ready
        #expect(!interpolator.isReady)
        #expect(interpolator.latestValidFrame == nil)
    }
}
