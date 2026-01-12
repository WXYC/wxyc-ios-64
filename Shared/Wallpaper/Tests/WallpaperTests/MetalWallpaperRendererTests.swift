//
//  MetalWallpaperRendererTests.swift
//  WallpaperTests
//
//  Tests for MetalWallpaperRenderer, particularly snapshot capture functionality.
//
//  Note: These tests require Metal shader compilation which only happens in Xcode builds.
//  When running via `swift test`, the Metal library won't be available and tests will skip.
//  Run these tests through Xcode for full coverage.
//

import Foundation
import Metal
import MetalKit
import Testing
@testable import Wallpaper

@Suite("MetalWallpaperRenderer")
@MainActor
struct MetalWallpaperRendererTests {

    /// Checks if the Metal library is available (only true when running in Xcode).
    private func isMetalLibraryAvailable(device: MTLDevice) -> Bool {
        // Try to load the Metal library from the bundle
        guard let _ = try? device.makeDefaultLibrary(bundle: Bundle.module) else {
            return false
        }
        return true
    }

    // MARK: - captureSnapshot Tests

    @Test("captureSnapshot returns valid image for stitchable shader with parameters")
    func captureSnapshotStitchableShaderWithParameters() async {
        guard let device = MTLCreateSystemDefaultDevice() else {
            Issue.record("Metal device not available")
            return
        }

        // Skip if Metal library not available (SPM test environment)
        guard isMetalLibraryAvailable(device: device) else {
            // Not a failure - Metal shaders only compile in Xcode
            return
        }

        // Find a stitchable theme with parameters (like ChromaWave/Hypervalent)
        let stitchableTheme = ThemeRegistry.shared.themes.first { theme in
            theme.manifest.renderer.type == .stitchable &&
            !theme.manifest.parameters.isEmpty
        }

        guard let theme = stitchableTheme else {
            Issue.record("No stitchable theme with parameters found in registry")
            return
        }

        // Create renderer
        let renderer = MetalWallpaperRenderer(
            theme: theme,
            directiveStore: nil,
            animationStartTime: Date(),
            qualityProfile: nil
        )

        // Configure with a Metal view
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 100, height: 100), device: device)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        renderer.configure(view: view)

        // Capture snapshot - this should not crash due to missing buffer binding
        let snapshot = renderer.captureSnapshot(size: CGSize(width: 50, height: 50))

        // Verify we got a valid image
        #expect(snapshot != nil, "captureSnapshot should return a valid image for stitchable shader with parameters")
    }

    @Test("captureSnapshot returns valid image for rawMetal shader with parameters")
    func captureSnapshotRawMetalShaderWithParameters() async {
        guard let device = MTLCreateSystemDefaultDevice() else {
            Issue.record("Metal device not available")
            return
        }

        // Skip if Metal library not available (SPM test environment)
        guard isMetalLibraryAvailable(device: device) else {
            return
        }

        // Find a rawMetal theme with parameters (like LavaLite)
        let rawMetalTheme = ThemeRegistry.shared.themes.first { theme in
            theme.manifest.renderer.type == .rawMetal &&
            !theme.manifest.parameters.isEmpty
        }

        guard let theme = rawMetalTheme else {
            Issue.record("No rawMetal theme with parameters found in registry")
            return
        }

        // Create renderer
        let renderer = MetalWallpaperRenderer(
            theme: theme,
            directiveStore: nil,
            animationStartTime: Date(),
            qualityProfile: nil
        )

        // Configure with a Metal view
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 100, height: 100), device: device)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        renderer.configure(view: view)

        // Capture snapshot
        let snapshot = renderer.captureSnapshot(size: CGSize(width: 50, height: 50))

        // Verify we got a valid image
        #expect(snapshot != nil, "captureSnapshot should return a valid image for rawMetal shader with parameters")
    }

    @Test("captureSnapshot handles theme without parameters")
    func captureSnapshotThemeWithoutParameters() async {
        guard let device = MTLCreateSystemDefaultDevice() else {
            Issue.record("Metal device not available")
            return
        }

        // Skip if Metal library not available (SPM test environment)
        guard isMetalLibraryAvailable(device: device) else {
            return
        }

        // Find a theme without parameters
        let themeWithoutParams = ThemeRegistry.shared.themes.first { theme in
            theme.manifest.parameters.isEmpty &&
            (theme.manifest.renderer.type == .stitchable || theme.manifest.renderer.type == .rawMetal)
        }

        guard let theme = themeWithoutParams else {
            // Skip if no such theme exists - this is fine
            return
        }

        // Create renderer
        let renderer = MetalWallpaperRenderer(
            theme: theme,
            directiveStore: nil,
            animationStartTime: Date(),
            qualityProfile: nil
        )

        // Configure with a Metal view
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 100, height: 100), device: device)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        renderer.configure(view: view)

        // Capture snapshot - should work even without parameters
        let snapshot = renderer.captureSnapshot(size: CGSize(width: 50, height: 50))

        #expect(snapshot != nil, "captureSnapshot should return a valid image for theme without parameters")
    }
}
