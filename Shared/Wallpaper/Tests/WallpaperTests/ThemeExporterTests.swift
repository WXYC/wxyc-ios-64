//
//  ThemeExporterTests.swift
//  WallpaperTests
//
//  Tests for ThemeExporter functionality.
//

import Testing
import Foundation
import ZIPFoundation
@testable import Wallpaper

@Suite("ThemeExporter")
@MainActor
struct ThemeExporterTests {

    private func makeTestDefaults() -> UserDefaults {
        let suiteName = "ThemeExporterTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    /// Unzips a file to a destination directory using ZIPFoundation (iOS-compatible)
    private func unzip(_ zipURL: URL, to destinationDir: URL) throws {
        let fileManager = FileManager.default
        try fileManager.unzipItem(at: zipURL, to: destinationDir)
    }

    @Test("Exports all themes to zip file")
    func exportsAllThemesToZip() async throws {
        let registry = MockThemeRegistry.withTestThemes()
        let defaults = makeTestDefaults()
        let config = ThemeConfiguration(registry: registry, defaults: defaults)
        let exporter = ThemeExporter(registry: registry, configuration: config)

        let zipURL = try await exporter.exportAllThemes()

        #expect(FileManager.default.fileExists(atPath: zipURL.path))
        #expect(zipURL.pathExtension == "zip")

        // Clean up
        try? FileManager.default.removeItem(at: zipURL)
    }

    @Test("Exported zip contains JSON files for each theme")
    func exportedZipContainsJSONFiles() async throws {
        let registry = MockThemeRegistry.withTestThemes()
        let defaults = makeTestDefaults()
        let config = ThemeConfiguration(registry: registry, defaults: defaults)
        let exporter = ThemeExporter(registry: registry, configuration: config)

        let zipURL = try await exporter.exportAllThemes()

        // Unzip to inspect contents
        let unzipDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: unzipDir, withIntermediateDirectories: true)

        try unzip(zipURL, to: unzipDir)

        // Check for expected JSON files
        let wallpapersDir = unzipDir.appending(path: "Wallpapers")
        let contents = try FileManager.default.contentsOfDirectory(atPath: wallpapersDir.path)

        #expect(contents.contains("test_dark.json"))
        #expect(contents.contains("test_light.json"))

        // Clean up
        try? FileManager.default.removeItem(at: zipURL)
        try? FileManager.default.removeItem(at: unzipDir)
    }

    @Test("Exported JSON contains merged overrides")
    func exportedJSONContainsMergedOverrides() async throws {
        let registry = MockThemeRegistry.withTestThemes()
        let defaults = makeTestDefaults()
        let config = ThemeConfiguration(registry: registry, defaults: defaults)

        // Set some overrides for the default theme
        config.selectedThemeID = "test_dark"
        config.accentHueOverride = 200
        config.overlayOpacityOverride = 0.5

        let exporter = ThemeExporter(registry: registry, configuration: config)
        let zipURL = try await exporter.exportAllThemes()

        // Unzip to inspect contents
        let unzipDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: unzipDir, withIntermediateDirectories: true)

        try unzip(zipURL, to: unzipDir)

        // Read the exported JSON
        let jsonURL = unzipDir.appending(path: "Wallpapers/test_dark.json")
        let data = try Data(contentsOf: jsonURL)
        let manifest = try JSONDecoder().decode(ThemeManifest.self, from: data)

        // Verify overrides are merged
        #expect(manifest.accent.hue == 200)
        #expect(manifest.overlayOpacity == 0.5)

        // Clean up
        try? FileManager.default.removeItem(at: zipURL)
        try? FileManager.default.removeItem(at: unzipDir)
    }

    @Test("Exported JSON preserves theme identity")
    func exportedJSONPreservesThemeIdentity() async throws {
        let registry = MockThemeRegistry.withTestThemes()
        let defaults = makeTestDefaults()
        let config = ThemeConfiguration(registry: registry, defaults: defaults)
        let exporter = ThemeExporter(registry: registry, configuration: config)

        let zipURL = try await exporter.exportAllThemes()

        // Unzip to inspect contents
        let unzipDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: unzipDir, withIntermediateDirectories: true)

        try unzip(zipURL, to: unzipDir)

        // Read the exported JSON
        let jsonURL = unzipDir.appending(path: "Wallpapers/test_dark.json")
        let data = try Data(contentsOf: jsonURL)
        let manifest = try JSONDecoder().decode(ThemeManifest.self, from: data)

        // Verify identity properties are preserved
        #expect(manifest.id == "test_dark")
        #expect(manifest.displayName == "Test Dark")
        #expect(manifest.version == "1.0.0")

        // Clean up
        try? FileManager.default.removeItem(at: zipURL)
        try? FileManager.default.removeItem(at: unzipDir)
    }

    @Test("Export with no overrides produces original values")
    func exportWithNoOverridesProducesOriginalValues() async throws {
        let registry = MockThemeRegistry.withTestThemes()
        let defaults = makeTestDefaults()
        let config = ThemeConfiguration(registry: registry, defaults: defaults)
        let exporter = ThemeExporter(registry: registry, configuration: config)

        let zipURL = try await exporter.exportAllThemes()

        // Unzip to inspect contents
        let unzipDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: unzipDir, withIntermediateDirectories: true)

        try unzip(zipURL, to: unzipDir)

        // Read the exported JSON
        let jsonURL = unzipDir.appending(path: "Wallpapers/test_dark.json")
        let data = try Data(contentsOf: jsonURL)
        let manifest = try JSONDecoder().decode(ThemeManifest.self, from: data)

        // Verify original values from testDarkTheme
        #expect(manifest.accent.hue == 30)
        #expect(manifest.accent.saturation == 0.8)
        #expect(manifest.blurRadius == 8.0)
        #expect(manifest.overlayOpacity == 0.15)

        // Clean up
        try? FileManager.default.removeItem(at: zipURL)
        try? FileManager.default.removeItem(at: unzipDir)
    }

    @Test("Export cleans up temp directory")
    func exportCleansUpTempDirectory() async throws {
        let registry = MockThemeRegistry.withTestThemes()
        let defaults = makeTestDefaults()
        let config = ThemeConfiguration(registry: registry, defaults: defaults)
        let exporter = ThemeExporter(registry: registry, configuration: config)

        let zipURL = try await exporter.exportAllThemes()

        // The temp ThemeExport directory should be cleaned up
        let tempDir = FileManager.default.temporaryDirectory
        let contents = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        let exportDirs = contents.filter { $0.hasPrefix("ThemeExport-") }

        #expect(exportDirs.isEmpty)

        // Clean up
        try? FileManager.default.removeItem(at: zipURL)
    }
}
