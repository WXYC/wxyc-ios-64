//
//  ModelSeeder.swift
//  OpenNSFW
//
//  Seeds the OpenNSFW model to the shared app group container
//  so widget extensions can access it without bundling their own copy.
//

import Foundation

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
        guard let destURL = sharedModelURL else {
            // App group container not available
            return
        }
        
        let currentVersion = modelVersion(at: bundleModelURL)
        let seededVersion = UserDefaults(suiteName: containerID)?.string(forKey: versionKey)
        
        // Skip if already seeded with current version
        guard seededVersion != currentVersion else {
            return
        }
        
        // Remove old version if exists
        if FileManager.default.fileExists(atPath: destURL.path) {
            try? FileManager.default.removeItem(at: destURL)
        }
        
        // Copy model directory to shared container
        do {
            try FileManager.default.copyItem(at: bundleModelURL, to: destURL)
            UserDefaults(suiteName: containerID)?.set(currentVersion, forKey: versionKey)
        } catch {
            // Seeding failed - widget will fall back to permissive behavior
            #if DEBUG
            print("ModelSeeder: Failed to seed model - \(error)")
            #endif
        }
    }
    
    /// Computes a version identifier for the model based on its metadata.
    private static func modelVersion(at url: URL) -> String {
        let metadataURL = url.appendingPathComponent("metadata.json")
        
        guard let data = try? Data(contentsOf: metadataURL) else {
            // Fall back to modification date if metadata unavailable
            return modificationDate(at: url)
        }
        
        // Use hash of metadata content as version
        var hasher = Hasher()
        hasher.combine(data)
        return String(hasher.finalize())
    }
    
    /// Falls back to using the directory modification date as version.
    private static func modificationDate(at url: URL) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attrs[.modificationDate] as? Date else {
            return "unknown"
        }
        return String(date.timeIntervalSince1970)
    }
}


