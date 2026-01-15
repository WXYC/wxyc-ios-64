//
//  ComputePipelineManagerTests.swift
//  WallpaperTests
//
//  Tests for ComputePipelineManager compute shader infrastructure.
//

import Testing
import Metal
@testable import Wallpaper

@Suite("ComputePipelineManager Tests")
struct ComputePipelineManagerTests {

    // MARK: - Error Tests

    @Suite("Compute Errors")
    struct ComputeErrorTests {

        @Test("functionNotFound error provides descriptive message")
        func functionNotFoundErrorMessage() {
            let error = ComputePipelineManager.ComputeError.functionNotFound("testKernel")
            #expect(error.errorDescription == "Compute function 'testKernel' not found")
        }

        @Test("pipelineCreationFailed error provides descriptive message")
        func pipelineCreationFailedErrorMessage() {
            let error = ComputePipelineManager.ComputeError.pipelineCreationFailed("Metal device unavailable")
            #expect(error.errorDescription == "Failed to create compute pipeline: Metal device unavailable")
        }
    }

    // MARK: - PersistentTexture Tests

    @Suite("PersistentTexture")
    struct PersistentTextureTests {

        @Test("Single-buffered texture does not swap")
        func singleBufferedNoSwap() throws {
            guard let device = MTLCreateSystemDefaultDevice() else {
                throw TestSkipCondition.deviceUnavailable
            }

            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: 64,
                height: 64,
                mipmapped: false
            )
            descriptor.usage = [.shaderRead, .shaderWrite]

            guard let texture = device.makeTexture(descriptor: descriptor) else {
                throw TestSkipCondition.textureCreationFailed
            }

            var persistentTexture = ComputePipelineManager.PersistentTexture(
                name: "test",
                textures: [texture],
                isDoubleBuffered: false
            )

            let currentBefore = persistentTexture.current
            let previousBefore = persistentTexture.previous
            #expect(currentBefore === previousBefore) // Same texture when single-buffered

            persistentTexture.swap()

            let currentAfter = persistentTexture.current
            #expect(currentAfter === currentBefore) // No change after swap
        }

        @Test("Double-buffered texture swaps correctly")
        func doubleBufferedSwaps() throws {
            guard let device = MTLCreateSystemDefaultDevice() else {
                throw TestSkipCondition.deviceUnavailable
            }

            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: 64,
                height: 64,
                mipmapped: false
            )
            descriptor.usage = [.shaderRead, .shaderWrite]

            guard let texture0 = device.makeTexture(descriptor: descriptor),
                  let texture1 = device.makeTexture(descriptor: descriptor) else {
                throw TestSkipCondition.textureCreationFailed
            }

            var persistentTexture = ComputePipelineManager.PersistentTexture(
                name: "test",
                textures: [texture0, texture1],
                isDoubleBuffered: true
            )

            // Initial state: index 0
            #expect(persistentTexture.current === texture0)
            #expect(persistentTexture.previous === texture1)

            // After first swap: index 1
            persistentTexture.swap()
            #expect(persistentTexture.current === texture1)
            #expect(persistentTexture.previous === texture0)

            // After second swap: back to index 0
            persistentTexture.swap()
            #expect(persistentTexture.current === texture0)
            #expect(persistentTexture.previous === texture1)
        }
    }

    // MARK: - Initialization Tests

    @Suite("Initialization")
    struct InitializationTests {

        @Test("Manager initializes with device")
        func initializesWithDevice() throws {
            guard let device = MTLCreateSystemDefaultDevice() else {
                throw TestSkipCondition.deviceUnavailable
            }

            let manager = ComputePipelineManager(device: device)
            #expect(manager.isReady == false) // Not ready until setUp is called
        }
    }

    // MARK: - Test Helpers

    enum TestSkipCondition: Error {
        case deviceUnavailable
        case textureCreationFailed
    }
}
