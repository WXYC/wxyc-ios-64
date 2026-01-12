import Foundation
import Logger

// MARK: - CacheMigrationManager

/// Manages cache invalidation when the app version changes.
///
/// `CacheMigrationManager` detects when the app's marketing version has changed
/// and automatically purges all caches to prevent stale or incompatible data
/// from causing issues after updates.
///
/// ## Why Version-Based Cache Invalidation?
///
/// Cache formats may change between app versions. Attempting to read data cached
/// by an older version could cause crashes or incorrect behavior. By purging
/// caches on version change, we ensure a clean slate for the new version.
///
/// ## Usage
///
/// Call ``migrateIfNeeded()`` early in the app launch sequence:
///
/// ```swift
/// @main
/// struct WXYCApp: App {
///     init() {
///         CacheMigrationManager.migrateIfNeeded()
///         // ... other initialization
///     }
/// }
/// ```
///
/// ## Storage Locations
///
/// This manager clears both:
/// - The app's private caches directory (`~/Library/Caches`)
/// - The shared App Group container caches (`group.wxyc.iphone/Library/Caches`)
public enum CacheMigrationManager {
    // MARK: - Private Constants

    /// UserDefaults key for tracking the last known app version.
    private static let lastKnownVersionKey = "CacheMigrationManager.lastKnownVersion"

    /// The App Group identifier for the shared container.
    private static let appGroupID = "group.wxyc.iphone"

    // MARK: - Public API

    /// Checks if the app version has changed and purges caches if needed.
    ///
    /// Call this method early in the app launch sequence, before accessing
    /// any cached data. If the marketing version has changed since the last
    /// launch, all caches are cleared and the new version is recorded.
    ///
    /// - Note: This method uses ``UserDefaults/wxyc`` (the shared App Group
    ///   UserDefaults) to persist the version across launches.
    public static func migrateIfNeeded() {
        let currentVersion = Bundle.main.marketingVersion
        let lastKnownVersion = UserDefaults.wxyc.string(forKey: lastKnownVersionKey)

        // Check if version has changed since last launch
        if lastKnownVersion != currentVersion {
            Log(.info, "Version changed from \(lastKnownVersion ?? "nil") to \(currentVersion). Purging cache.")
            purgeAllCaches()
            // Record the new version to prevent re-purging on next launch
            UserDefaults.wxyc.set(currentVersion, forKey: lastKnownVersionKey)
        }
    }

    // MARK: - Private Methods

    /// Removes all files from both the private and shared cache directories.
    private static func purgeAllCaches() {
        // Clear the app's private cache directory
        if let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)
                .forEach { try? FileManager.default.removeItem(at: $0) }
        }

        // Clear the shared App Group container's cache directory
        if let sharedCacheDir = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("Library/Caches", isDirectory: true) {
            try? FileManager.default.contentsOfDirectory(at: sharedCacheDir, includingPropertiesForKeys: nil)
                .forEach { try? FileManager.default.removeItem(at: $0) }
        }
    }
}

// MARK: - Bundle Extension

private extension Bundle {
    /// The app's marketing version (e.g., "1.2.3") from Info.plist.
    ///
    /// Falls back to "0.0.0" if the version string is not available.
    var marketingVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
}

