import Foundation
import Metal
import Testing
@testable import Wallpaper

@Suite("ScaledRenderTarget")
struct ScaledRenderTargetTests {

    @Test("Scaled size calculation at 0.5 scale")
    func scaledSizeCalculation() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            Issue.record("Metal device not available")
            return
        }

        var target = ScaledRenderTarget()
        let viewSize = CGSize(width: 1000, height: 2000)

        _ = target.update(
            device: device,
            viewSize: viewSize,
            scale: 0.5,
            pixelFormat: .bgra8Unorm
        )

        #expect(target.scaledSize == CGSize(width: 500, height: 1000))
    }

    @Test("Scaled size calculation at 0.75 scale")
    func scaledSizeAt75Percent() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            Issue.record("Metal device not available")
            return
        }

        var target = ScaledRenderTarget()
        let viewSize = CGSize(width: 1000, height: 2000)

        _ = target.update(
            device: device,
            viewSize: viewSize,
            scale: 0.75,
            pixelFormat: .bgra8Unorm
        )

        #expect(target.scaledSize == CGSize(width: 750, height: 1500))
    }

    @Test("No texture created at scale 1.0")
    func noTextureAtFullScale() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            Issue.record("Metal device not available")
            return
        }

        var target = ScaledRenderTarget()

        _ = target.update(
            device: device,
            viewSize: CGSize(width: 1000, height: 2000),
            scale: 1.0,
            pixelFormat: .bgra8Unorm
        )

        #expect(target.renderTexture == nil)
        #expect(target.scaledSize == CGSize(width: 1000, height: 2000))
    }

    @Test("Texture created at scale < 1.0")
    func textureCreatedAtScaledSize() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            Issue.record("Metal device not available")
            return
        }

        var target = ScaledRenderTarget()

        _ = target.update(
            device: device,
            viewSize: CGSize(width: 1000, height: 2000),
            scale: 0.5,
            pixelFormat: .bgra8Unorm
        )

        #expect(target.renderTexture != nil)
        #expect(target.renderTexture?.width == 500)
        #expect(target.renderTexture?.height == 1000)
    }

    @Test("Texture recreated on size change")
    func textureRecreatedOnSizeChange() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            Issue.record("Metal device not available")
            return
        }

        var target = ScaledRenderTarget()

        let changed1 = target.update(
            device: device,
            viewSize: CGSize(width: 1000, height: 2000),
            scale: 0.5,
            pixelFormat: .bgra8Unorm
        )
        #expect(changed1)

        let firstTexture = target.renderTexture

        let changed2 = target.update(
            device: device,
            viewSize: CGSize(width: 1200, height: 2400),
            scale: 0.5,
            pixelFormat: .bgra8Unorm
        )
        #expect(changed2)

        let secondTexture = target.renderTexture

        // Textures should be different (new texture created for new size)
        #expect(firstTexture !== secondTexture)
        #expect(secondTexture?.width == 600)
        #expect(secondTexture?.height == 1200)
    }

    @Test("Texture reused when unchanged")
    func textureReusedWhenUnchanged() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            Issue.record("Metal device not available")
            return
        }

        var target = ScaledRenderTarget()

        _ = target.update(
            device: device,
            viewSize: CGSize(width: 1000, height: 2000),
            scale: 0.5,
            pixelFormat: .bgra8Unorm
        )

        let firstTexture = target.renderTexture

        let changed = target.update(
            device: device,
            viewSize: CGSize(width: 1000, height: 2000),
            scale: 0.5,
            pixelFormat: .bgra8Unorm
        )

        // Should not have changed
        #expect(!changed)

        let secondTexture = target.renderTexture

        // Same texture should be reused
        #expect(firstTexture === secondTexture)
    }

    @Test("Texture recreated on scale change")
    func textureRecreatedOnScaleChange() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            Issue.record("Metal device not available")
            return
        }

        var target = ScaledRenderTarget()

        _ = target.update(
            device: device,
            viewSize: CGSize(width: 1000, height: 2000),
            scale: 0.5,
            pixelFormat: .bgra8Unorm
        )

        let firstTexture = target.renderTexture
        #expect(firstTexture?.width == 500)

        let changed = target.update(
            device: device,
            viewSize: CGSize(width: 1000, height: 2000),
            scale: 0.75,
            pixelFormat: .bgra8Unorm
        )

        #expect(changed)

        let secondTexture = target.renderTexture
        #expect(secondTexture?.width == 750)
        #expect(firstTexture !== secondTexture)
    }

    @Test("Transition from scaled to full resolution")
    func transitionToFullResolution() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            Issue.record("Metal device not available")
            return
        }

        var target = ScaledRenderTarget()

        _ = target.update(
            device: device,
            viewSize: CGSize(width: 1000, height: 2000),
            scale: 0.5,
            pixelFormat: .bgra8Unorm
        )

        #expect(target.renderTexture != nil)

        let changed = target.update(
            device: device,
            viewSize: CGSize(width: 1000, height: 2000),
            scale: 1.0,
            pixelFormat: .bgra8Unorm
        )

        #expect(changed)
        #expect(target.renderTexture == nil)
    }
}
