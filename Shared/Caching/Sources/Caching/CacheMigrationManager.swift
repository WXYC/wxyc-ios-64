//
//  CacheMigrationManager.swift
//  Core
//
//  Detects marketing version changes and purges the cache to prevent
//  stale or incompatible data from causing issues.
//

import Foundation
import Logger

public enum CacheMigrationManager {
    private static let lastKnownVersionKey = "CacheMigrationManager.lastKnownVersion"
    
    /// Call at app launch to purge cache if marketing version changed
    public static func migrateIfNeeded() {
        let currentVersion = Bundle.main.marketingVersion
        let lastKnownVersion = UserDefaults.wxyc.string(forKey: lastKnownVersionKey)
        
        if lastKnownVersion != currentVersion {
            Log(.info, "Version changed from \(lastKnownVersion ?? "nil") to \(currentVersion). Purging cache.")
            purgeAllCaches()
            UserDefaults.wxyc.set(currentVersion, forKey: lastKnownVersionKey)
        }
    }
    
    private static let appGroupID = "group.wxyc.iphone"
    
    private static func purgeAllCaches() {
        // Clear private cache directory
        if let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)
                .forEach { try? FileManager.default.removeItem(at: $0) }
        }
        
        // Clear shared container cache directory
        if let sharedCacheDir = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("Library/Caches", isDirectory: true) {
            try? FileManager.default.contentsOfDirectory(at: sharedCacheDir, includingPropertiesForKeys: nil)
                .forEach { try? FileManager.default.removeItem(at: $0) }
        }
    }
}

private extension Bundle {
    var marketingVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
}

