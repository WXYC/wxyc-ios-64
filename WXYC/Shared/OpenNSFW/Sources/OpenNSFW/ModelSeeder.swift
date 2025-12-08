//
//  ModelSeeder.swift
//  OpenNSFW
//
//  Seeds the OpenNSFW model to the shared app group container
//  so widget extensions can access it without bundling their own copy.
//

import Foundation
import Logger

public enum ModelSeeder {
    private static let containerID = "group.wxyc.iphone"
    private static let modelDirectoryName = "OpenNSFW.mlmodelc"
    private static let versionKey = "OpenNSFW.modelVersion"
    
    /// URL to the model in the shared app group container.
    /// Returns nil if the app group container is not available.
    public static var sharedModelURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: containerID)?
            .appendingPathComponent(modelDirectoryName)
    }
    
    /// Seeds the model to the shared container if needed.
    /// Call this from the main app on launch to ensure the widget can access the model.
    ///
    /// - Parameter bundleModelURL: URL to the model in the main app's bundle
    public static func seedIfNeeded(bundleModelURL: URL) {
        Log(.info, "ModelSeeder: seedIfNeeded called with bundleModelURL: \(bundleModelURL.path)")
        
        guard let destURL = sharedModelURL else {
            Log(.error, "ModelSeeder: App group container not available for identifier '\(containerID)'")
            return
        }
        
        let currentVersion = modelVersion(at: bundleModelURL)
        let seededVersion = UserDefaults(suiteName: containerID)?.string(forKey: versionKey)
        
        Log(.info, "ModelSeeder: Current version: \(currentVersion), Seeded version: \(seededVersion ?? "nil")")
        
        // Skip if already seeded with current version
        guard seededVersion != currentVersion else {
            Log(.info, "ModelSeeder: Model already seeded with current version, skipping")
            return
        }
        
        // Remove old version if exists
        if FileManager.default.fileExists(atPath: destURL.path) {
            Log(.info, "ModelSeeder: Removing old model at \(destURL.path)")
            try? FileManager.default.removeItem(at: destURL)
        }
        
        // Copy model directory to shared container
        do {
            Log(.info, "ModelSeeder: Copying model from \(bundleModelURL.path) to \(destURL.path)")
            try FileManager.default.copyItem(at: bundleModelURL, to: destURL)
            UserDefaults(suiteName: containerID)?.set(currentVersion, forKey: versionKey)
            Log(.info, "ModelSeeder: Successfully seeded model with version \(currentVersion)")
        } catch {
            Log(.error, "ModelSeeder: Failed to seed model - \(error)")
        }
    }
    
    /// Computes a version identifier for the model based on its metadata.
    private static func modelVersion(at url: URL) -> String {
        let metadataURL = url.appendingPathComponent("metadata.json")
        
        guard let data = try? Data(contentsOf: metadataURL) else {
            Log(.info, "ModelSeeder: No metadata.json found, falling back to modification date")
            return modificationDate(at: url)
        }
        
        // Use hash of metadata content as version
        var hasher = Hasher()
        hasher.combine(data)
        let version = String(hasher.finalize())
        Log(.info, "ModelSeeder: Computed version from metadata hash: \(version)")
        return version
    }
    
    /// Falls back to using the directory modification date as version.
    private static func modificationDate(at url: URL) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attrs[.modificationDate] as? Date else {
            Log(.warning, "ModelSeeder: Could not get modification date, returning 'unknown'")
            return "unknown"
        }
        let version = String(date.timeIntervalSince1970)
        Log(.info, "ModelSeeder: Using modification date as version: \(version)")
        return version
    }
}


