//
//  WallpaperSnapshotService.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/20/25.
//

import Foundation
import MetalKit
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Service for generating static snapshot images from wallpaper renderers.
/// Used by the wallpaper picker to show non-live previews of wallpapers.
@MainActor
public final class WallpaperSnapshotService {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let sampler: MTLSamplerState
    private let noiseTexture: MTLTexture

    /// Creates a snapshot service using the default Metal device.
    /// - Returns: A new snapshot service, or nil if Metal is not available.
    public init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            return nil
        }
        self.device = device
        self.commandQueue = queue

        // Create sampler for shaders that need it
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .repeat
        samplerDescriptor.tAddressMode = .repeat
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            return nil
        }
        self.sampler = sampler

        // Create noise texture for shaders that need it
        guard let noiseTexture = Self.makeNoiseTexture(device: device, size: 256) else {
            return nil
        }
        self.noiseTexture = noiseTexture
    }

    private static func makeNoiseTexture(device: MTLDevice, size: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: size,
            height: size,
            mipmapped: false
        )
        desc.usage = [.shaderRead]

        guard let tex = device.makeTexture(descriptor: desc) else {
            return nil
        }

        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let v = UInt8.random(in: 0...255)
            bytes[i + 0] = v
            bytes[i + 1] = v
            bytes[i + 2] = v
            bytes[i + 3] = 255
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

    // MARK: - Public API

    /// Generates snapshots for all wallpapers at the given size.
    /// Snapshots are yielded as they complete via an async stream.
    /// - Parameters:
    ///   - size: The size to render snapshots at.
    ///   - scale: The display scale factor.
    /// - Returns: An async stream of wallpaper snapshots.
    public func generateSnapshots(
        size: CGSize,
        scale: CGFloat
    ) -> AsyncStream<WallpaperSnapshot> {
        AsyncStream { continuation in
            Task { @MainActor in
                for wallpaper in WallpaperRegistry.shared.wallpapers {
                    if let snapshot = await self.generateSnapshot(
                        for: wallpaper,
                        size: size,
                        scale: scale
                    ) {
                        continuation.yield(snapshot)
                    }
                }
                continuation.finish()
            }
        }
    }

    /// Generates a single snapshot for a specific wallpaper.
    /// - Parameters:
    ///   - wallpaper: The wallpaper to snapshot.
    ///   - size: The size to render at.
    ///   - scale: The display scale factor.
    /// - Returns: A snapshot if successful, nil otherwise.
    public func generateSnapshot(
        for wallpaper: LoadedWallpaper,
        size: CGSize,
        scale: CGFloat
    ) async -> WallpaperSnapshot? {
        // Capture the current time for animation synchronization
        let captureTime: Float = 0.0 // Start at t=0 for consistent previews

        let image: PlatformImage?

        // Determine if we can render via Metal (has fragmentFunction)
        let hasFragmentFunction = wallpaper.manifest.renderer.fragmentFunction != nil

        switch wallpaper.manifest.renderer.type {
        case .rawMetal:
            // Raw Metal shaders have a fragmentFunction we can use directly
            image = await renderMetalSnapshot(
                for: wallpaper,
                size: size,
                scale: scale,
                time: captureTime
            )
        case .stitchable:
            // Stitchable shaders with fragmentFunction can be rendered via Metal
            // SwiftUI ImageRenderer doesn't properly render Metal shader effects
            if hasFragmentFunction {
                image = await renderMetalSnapshot(
                    for: wallpaper,
                    size: size,
                    scale: scale,
                    time: captureTime
                )
            } else {
                image = await renderSwiftUISnapshot(
                    for: wallpaper,
                    size: size,
                    scale: scale
                )
            }
        case .multipass, .swiftUI, .composite:
            // Composite/swiftUI are SwiftUI views, can be rendered via ImageRenderer
            image = await renderSwiftUISnapshot(
                for: wallpaper,
                size: size,
                scale: scale
            )
        }

        guard let image else { return nil }

        return WallpaperSnapshot(
            wallpaperID: wallpaper.id,
            image: image,
            captureTime: captureTime
        )
    }

    // MARK: - Metal Snapshot Rendering

    private func renderMetalSnapshot(
        for wallpaper: LoadedWallpaper,
        size: CGSize,
        scale: CGFloat,
        time: Float
    ) async -> PlatformImage? {
        let pixelWidth = Int(size.width * scale)
        let pixelHeight = Int(size.height * scale)

        // Create offscreen texture
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: pixelWidth,
            height: pixelHeight,
            mipmapped: false
        )
        textureDescriptor.usage = [.renderTarget, .shaderRead]
        textureDescriptor.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            return nil
        }

        // Get the fragment function name from the manifest
        let renderer = wallpaper.manifest.renderer
        guard let fragmentFn = renderer.fragmentFunction else {
            // No fragment function specified - can't render Metal snapshot
            return nil
        }

        // Load shader library
        guard let library = try? device.makeDefaultLibrary(bundle: Bundle.module) else {
            return nil
        }

        guard let vertexFunc = library.makeFunction(name: "fullscreenVertex"),
              let fragmentFunc = library.makeFunction(name: fragmentFn) else {
            return nil
        }

        // Create render pipeline
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunc
        pipelineDescriptor.fragmentFunction = fragmentFunc
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        guard let pipeline = try? await device.makeRenderPipelineState(descriptor: pipelineDescriptor) else {
            return nil
        }

        // Create render pass descriptor
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        // Create command buffer and render
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return nil
        }

        // Set up uniforms (minimal 16-byte struct compatible with all shaders)
        var uniforms = SnapshotUniforms(
            resolution: SIMD2(Float(pixelWidth), Float(pixelHeight)),
            time: time * (renderer.timeScale ?? 1.0),
            pad: 0
        )

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SnapshotUniforms>.stride, index: 0)
        encoder.setFragmentTexture(noiseTexture, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)

        // Draw fullscreen triangle
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commandBuffer.commit()
        await commandBuffer.completed()

        // Extract image from texture
        return extractImage(from: texture, size: size, scale: scale)
    }

    /// Uniforms struct for snapshot rendering.
    /// Uses the minimal 16-byte struct that all shaders support.
    /// Shaders with larger Uniforms will just ignore the extra fields they expect.
    private struct SnapshotUniforms {
        var resolution: SIMD2<Float>  // 8 bytes
        var time: Float               // 4 bytes
        var pad: Float                // 4 bytes
    }

    private func extractImage(from texture: MTLTexture, size: CGSize, scale: CGFloat) -> PlatformImage? {
        let pixelWidth = texture.width
        let pixelHeight = texture.height
        let bytesPerRow = pixelWidth * 4

        var pixelData = [UInt8](repeating: 0, count: bytesPerRow * pixelHeight)
        texture.getBytes(
            &pixelData,
            bytesPerRow: bytesPerRow,
            from: MTLRegion(
                origin: MTLOrigin(x: 0, y: 0, z: 0),
                size: MTLSize(width: pixelWidth, height: pixelHeight, depth: 1)
            ),
            mipmapLevel: 0
        )

        // Convert BGRA to RGBA
        for i in stride(from: 0, to: pixelData.count, by: 4) {
            let b = pixelData[i]
            let r = pixelData[i + 2]
            pixelData[i] = r
            pixelData[i + 2] = b
        }

        guard let provider = CGDataProvider(data: Data(pixelData) as CFData),
              let cgImage = CGImage(
                  width: pixelWidth,
                  height: pixelHeight,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: bytesPerRow,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: true,
                  intent: .defaultIntent
              ) else {
            return nil
        }

        #if canImport(UIKit)
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
        #elseif canImport(AppKit)
        return NSImage(cgImage: cgImage, size: NSSize(width: pixelWidth, height: pixelHeight))
        #endif
    }

    // MARK: - SwiftUI Snapshot Rendering

    @MainActor
    private func renderSwiftUISnapshot(
        for wallpaper: LoadedWallpaper,
        size: CGSize,
        scale: CGFloat
    ) async -> PlatformImage? {
        let view = WallpaperRendererFactory.makeView(for: wallpaper, audioData: nil)
            .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: view)
        renderer.scale = scale

        #if canImport(UIKit)
        return renderer.uiImage
        #elseif canImport(AppKit)
        return renderer.nsImage
        #endif
    }
}
