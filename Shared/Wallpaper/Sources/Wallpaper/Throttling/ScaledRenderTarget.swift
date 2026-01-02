import Foundation
import Metal

/// Manages an intermediate texture for scaled rendering.
///
/// When the resolution scale is less than 1.0, the renderer draws to this
/// smaller texture and then upscales to the full drawable.
struct ScaledRenderTarget {

    /// The intermediate texture to render into, or nil when rendering at full scale.
    private(set) var renderTexture: MTLTexture?

    /// The current resolution scale factor.
    private var currentScale: Float = 1.0

    /// The current view size in pixels.
    private var currentSize: CGSize = .zero

    /// The current pixel format.
    private var currentPixelFormat: MTLPixelFormat = .bgra8Unorm

    /// The scaled resolution for shader uniforms.
    var scaledSize: CGSize {
        CGSize(
            width: currentSize.width * CGFloat(currentScale),
            height: currentSize.height * CGFloat(currentScale)
        )
    }

    /// Updates the render target if scale or size changed.
    ///
    /// - Parameters:
    ///   - device: Metal device for texture creation.
    ///   - viewSize: The full drawable size in pixels.
    ///   - scale: Resolution scale factor (1.0 = full, 0.5 = half).
    ///   - pixelFormat: Pixel format for the texture.
    /// - Returns: `true` if the target was updated, `false` if unchanged.
    mutating func update(
        device: MTLDevice,
        viewSize: CGSize,
        scale: Float,
        pixelFormat: MTLPixelFormat
    ) -> Bool {
        // Check if anything changed
        if currentSize == viewSize &&
           currentScale == scale &&
           currentPixelFormat == pixelFormat {
            return false
        }

        currentSize = viewSize
        currentScale = scale
        currentPixelFormat = pixelFormat

        // At full scale, no intermediate texture needed
        if scale >= 1.0 {
            renderTexture = nil
            return true
        }

        // Create scaled texture
        let scaledWidth = Int(viewSize.width * CGFloat(scale))
        let scaledHeight = Int(viewSize.height * CGFloat(scale))

        guard scaledWidth > 0, scaledHeight > 0 else {
            renderTexture = nil
            return true
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: scaledWidth,
            height: scaledHeight,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private

        renderTexture = device.makeTexture(descriptor: descriptor)

        return true
    }
}
