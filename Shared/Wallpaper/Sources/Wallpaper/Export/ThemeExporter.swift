//
//  ThemeExporter.swift
//  Wallpaper
//
//  Exports theme configuration as shareable files.
//
//  Created by Jake Bromberg on 01/11/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Error types for theme export operations.
public enum ThemeExportError: Error, LocalizedError {
    case resourceNotFound(String)
    case copyFailed(String, Error)
    case encodingFailed(String, Error)
    case zipFailed(Error)
    case tempDirectoryCreationFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .resourceNotFound(let name):
            "Resource not found: \(name)"
        case .copyFailed(let path, let error):
            "Failed to copy \(path): \(error.localizedDescription)"
        case .encodingFailed(let theme, let error):
            "Failed to encode manifest for \(theme): \(error.localizedDescription)"
        case .zipFailed(let error):
            "Failed to create zip archive: \(error.localizedDescription)"
        case .tempDirectoryCreationFailed(let error):
            "Failed to create temp directory: \(error.localizedDescription)"
        }
    }
}

/// Service for exporting all themes with customizations as a shareable zip archive.
@MainActor
public final class ThemeExporter {
    private let registry: any ThemeRegistryProtocol
    private let configuration: ThemeConfiguration
    private let fileManager: FileManager

    public init(
        registry: any ThemeRegistryProtocol = ThemeRegistry.shared,
        configuration: ThemeConfiguration,
        fileManager: FileManager = .default
    ) {
        self.registry = registry
        self.configuration = configuration
        self.fileManager = fileManager
    }

    /// Exports all themes with their customizations to a zip archive.
    /// - Returns: URL of the created zip file ready for sharing.
    public func exportAllThemes() async throws -> URL {
        // Create temp directory
        let tempBase = fileManager.temporaryDirectory
        let exportID = UUID().uuidString
        let wallpapersDir = tempBase.appending(path: "ThemeExport-\(exportID)/Wallpapers")

        do {
            try fileManager.createDirectory(at: wallpapersDir, withIntermediateDirectories: true)
        } catch {
            throw ThemeExportError.tempDirectoryCreationFailed(error)
        }

        // Export each theme
        for theme in registry.themes {
            try exportTheme(theme, to: wallpapersDir)
        }

        // Create zip archive
        let zipURL = tempBase.appending(path: "Wallpapers-\(exportID).zip")
        try createZipArchive(from: wallpapersDir, to: zipURL)

        // Clean up temp directory
        let parentDir = wallpapersDir.deletingLastPathComponent()
        try? fileManager.removeItem(at: parentDir)

        return zipURL
    }

    // MARK: - Private

    private func exportTheme(_ theme: LoadedTheme, to wallpapersDir: URL) throws {
        // Write merged manifest JSON directly to wallpapers directory
        // Metal shaders are not included - copy them manually from source if needed
        let jsonFileName = "\(theme.id).json"
        try writeMergedManifest(for: theme, to: wallpapersDir, jsonFileName: jsonFileName)
    }

    private func writeMergedManifest(for theme: LoadedTheme, to dir: URL, jsonFileName: String) throws {
        let themeID = theme.id

        // Get overrides for this theme from ThemeConfiguration
        let overrides = configuration.overrides(for: themeID)

        // Apply overrides and update parameter defaults
        var mergedManifest = theme.manifest.applying(overrides)
        mergedManifest = applyParameterValues(from: theme.parameterStore, to: mergedManifest)

        // Encode with pretty printing
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data: Data
        do {
            data = try encoder.encode(mergedManifest)
        } catch {
            throw ThemeExportError.encodingFailed(themeID, error)
        }

        let jsonURL = dir.appending(path: jsonFileName)
        try data.write(to: jsonURL)
    }

    private func applyParameterValues(from store: ParameterStore, to manifest: ThemeManifest) -> ThemeManifest {
        // Update parameter definitions with current values as new defaults
        let updatedParameters = manifest.parameters.map { param -> ParameterDefinition in
            let newDefault: ParameterValue
            switch param.type {
            case .float:
                newDefault = .float(store.floatValue(for: param.id))
            case .float2:
                let (x, y) = store.float2Value(for: param.id)
                newDefault = .float2(x, y)
            case .float3:
                let (x, y, z) = store.float3Value(for: param.id)
                newDefault = .float3(x, y, z)
            case .bool:
                newDefault = .bool(store.boolValue(for: param.id))
            case .color:
                // Color parameters store individual components
                let r = store.colorComponent("r", for: param.id)
                let g = store.colorComponent("g", for: param.id)
                let b = store.colorComponent("b", for: param.id)
                newDefault = .float3(r, g, b)
            }

            return ParameterDefinition(
                id: param.id,
                type: param.type,
                label: param.label,
                group: param.group,
                defaultValue: newDefault,
                range: param.range,
                userDefaultsKey: param.userDefaultsKey,
                components: param.components
            )
        }

        return ThemeManifest(
            id: manifest.id,
            displayName: manifest.displayName,
            version: manifest.version,
            renderer: manifest.renderer,
            parameters: updatedParameters,
            shaderArguments: manifest.shaderArguments,
            foreground: manifest.foreground,
            accent: manifest.accent,
            buttonStyle: manifest.buttonStyle ?? .colored,
            blurRadius: manifest.blurRadius,
            overlayOpacity: manifest.overlayOpacity,
            overlayDarkness: manifest.overlayDarkness
        )
    }

    private func createZipArchive(from sourceDir: URL, to zipURL: URL) throws {
        // Use NSFileCoordinator with .forUploading to create a zip
        var error: NSError?
        var coordinatorError: Error?

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            readingItemAt: sourceDir,
            options: .forUploading,
            error: &error
        ) { tempZipURL in
            do {
                try self.fileManager.copyItem(at: tempZipURL, to: zipURL)
            } catch let copyError {
                coordinatorError = copyError
            }
        }

        if let error {
            throw ThemeExportError.zipFailed(error)
        }
        if let coordinatorError {
            throw ThemeExportError.zipFailed(coordinatorError)
        }
    }
}
